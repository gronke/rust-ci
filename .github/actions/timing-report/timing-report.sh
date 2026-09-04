#!/usr/bin/env bash
# Render the build-performance report to the job summary.
# Inputs arrive as env vars from action.yml:
#   TITLE     heading for the summary section
#   ORDER     "duration" (slowest first) or "chronological"
#   COLUMNS   sparkline width per stage
#   GITHUB_TOKEN  token for the Actions API (per-step timings); needs actions:read
set -euo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

dir="$(timing_dir)"

# Stop the sampler before reading its file, so the last stage's samples are a
# complete set rather than a set that grows during the parse.
if [ -f "$dir/sampler.pid" ]; then
  pid="$(cat "$dir/sampler.pid")"
  # setsid put the sampler in its own process group; kill the group so the
  # sleep it is parked in goes too, otherwise the job hangs at cleanup
  # waiting for a child that outlives the step it was started from.
  kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  rm -f "$dir/sampler.pid"
fi

# Stage boundaries, written to marks.tsv as `epoch_ms <TAB> name`, ascending.
# When a workflow places no manual marks, GitHub's own per-step timings are the
# source: no timing-mark steps are needed and even pre-step stages such as
# "Initialize containers" that in-job marks cannot see are captured. Emits the
# current job's completed steps plus a closing "__report" sentinel at the last
# step's end. Prints nothing (and returns non-zero) whenever the token, jq/curl,
# or the API response is unavailable, so the caller falls back to any marks.
marks_from_api() {
  local token="${GITHUB_TOKEN:-}"
  [ -n "$token" ] && [ -n "${GITHUB_RUN_ID:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || return 1
  command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || return 1
  local api="${GITHUB_API_URL:-https://api.github.com}" resp
  resp="$(curl -sSL --max-time 20 \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    "$api/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs?per_page=100" 2>/dev/null)" || return 1
  printf '%s' "$resp" | jq -e 'has("jobs")' >/dev/null 2>&1 || return 1
  # This job: the in-progress one on this runner (the report itself is a step of
  # it). Falls back to a runner match, then to the latest-started job, so the
  # selection still resolves when queried after the job completes (tests, reruns).
  local rows
  rows="$(printf '%s' "$resp" | jq -r --arg runner "${RUNNER_NAME:-}" '
    (.jobs // []) as $all
    | ($all | map(select(.status == "in_progress"))) as $inp
    | (if ($inp | length) > 0 then $inp else $all end) as $c
    | ($c | map(select(.runner_name == $runner))) as $byr
    | ((if ($byr | length) > 0 then $byr else $c end) | sort_by(.started_at) | last) as $job
    | (($job.steps // [])
        | map(select(.started_at != null and .completed_at != null))
        | sort_by(.number)) as $s
    | if ($s | length) == 0 then empty
      else (($s | map([.started_at, .name] | @tsv)) + [([$s[-1].completed_at, "__report"] | @tsv)])[]
      end
  ' 2>/dev/null)" || return 1
  [ -n "$rows" ] || return 1
  # ISO 8601 (second precision) -> epoch_ms; sanitize the name to stay tab-free.
  local iso name secs
  while IFS="$(printf '\t')" read -r iso name; do
    [ -n "$iso" ] || continue
    secs="$(date -u -d "$iso" +%s 2>/dev/null)" || return 1
    case "$secs" in '' | *[!0-9]*) return 1 ;; esac
    printf '%s\t%s\n' "$(( secs * 1000 ))" "$(timing_sanitize "$name")"
  done <<< "$rows"
}

if [ -s "$dir/marks.tsv" ]; then
  # Manual marks win. A workflow that still calls timing-mark instrumented its
  # stages on purpose, so honor them rather than overriding with raw step names;
  # dropping the marks is what opts a workflow into the API-derived stages below.
  # The last mark has no end until this sentinel closes it; the table drops it.
  timing_mark "__report"
elif marks_from_api > "$dir/marks.api.tsv" 2>/dev/null && [ -s "$dir/marks.api.tsv" ]; then
  # No manual marks: derive the stages from the Actions API. Its output already
  # ends with the __report sentinel, so no manual close is needed.
  mv "$dir/marks.api.tsv" "$dir/marks.tsv"
else
  rm -f "$dir/marks.api.tsv"
  echo "::warning title=No timing data::timing-report found no timing marks and could not read the Actions API (needs a token with actions:read)."
  exit 0
fi

# The render reads samples.tsv and notes.tsv. A report derived from the API
# without timing-start has neither, so create them empty: the table degrades to
# durations only rather than failing the awk (set -e + pipefail turns a missing
# input into a fatal exit), and the cores/sampler/cache lookups just find nothing.
[ -f "$dir/samples.tsv" ] || : > "$dir/samples.tsv"
[ -f "$dir/notes.tsv" ] || : > "$dir/notes.tsv"

cores="$(awk -F'\t' '$1 == "runner.cores" {print $2}' "$dir/notes.tsv" 2>/dev/null | tail -1)"
case "$cores" in '' | 0 | *[!0-9]*) cores=0 ;; esac

# One pass: marks define the stage bounds, samples are bucketed into them.
# Emits TSV per stage: name, ms, peak load, mean load, peak mem kB, shape.
stats="$dir/stages.tsv"
awk -F'\t' -v cols="$COLUMNS" -v cores="$cores" -v OFS='\t' '
  FNR == 1 { file++ }

  # marks.tsv
  file == 1 {
    n++
    at[n] = $1 + 0
    nm[n] = $2
    next
  }

  # samples.tsv: epoch_ms, cpu busy percent, mem used kB, mem total kB, disk kB
  file == 2 {
    ts = $1 + 0
    cpu = $2 + 0
    mem = $3 + 0
    # Binary search would be tidier; a job has tens of stages and a few
    # hundred samples, so the linear scan is not worth optimising away.
    for (i = 1; i < n; i++) {
      if (ts >= at[i] && ts < at[i + 1]) {
        cnt[i]++
        sum[i] += cpu
        if (cpu > peak[i]) peak[i] = cpu
        if (mem > pmem[i]) pmem[i] = mem
        span = at[i + 1] - at[i]
        b = (span > 0) ? int((ts - at[i]) * cols / span) : 0
        if (b >= cols) b = cols - 1
        if (b < 0) b = 0
        key = i SUBSEP b
        if (cpu > bmax[key]) bmax[key] = cpu
        seen[key] = 1
        break
      }
    }
    next
  }

  END {
    # The final mark is the sentinel; it closes stage n-1 and is not a stage.
    for (i = 1; i < n; i++) {
      dur = at[i + 1] - at[i]
      mean = (cnt[i] > 0) ? sum[i] / cnt[i] : 0
      shape = ""
      if (cnt[i] > 0) {
        # The samples are already a percentage of total CPU capacity, so a full
        # block is every core busy for that bucket with nothing to scale
        # against and no dependence on the core count being readable.
        for (b = 0; b < cols; b++) {
          key = i SUBSEP b
          if (!seen[key]) { shape = shape " "; continue }
          lvl = int(bmax[key] * 8 / 100)
          if (lvl < 1) lvl = 1
          if (lvl > 8) lvl = 8
          shape = shape sprintf("%d", lvl)
        }
      }
      print nm[i], dur, peak[i] + 0, mean, pmem[i] + 0, shape
    }
  }
' "$dir/marks.tsv" "$dir/samples.tsv" > "$stats"

total_ms="$(awk -F'\t' '{t += $2} END {print t + 0}' "$stats")"
sampled="$(awk -F'\t' '$6 ~ /[1-8]/ {c++} END {print c + 0}' "$stats")"

case "$ORDER" in
  chronological) sorted="$stats" ;;
  *) sort -t"$(printf '\t')" -k2,2nr "$stats" > "$stats.sorted"; sorted="$stats.sorted" ;;
esac

fmt_ms() {
  awk -v ms="$1" 'BEGIN {
    s = int(ms / 1000)
    if (s >= 3600) printf "%dh %02dm %02ds\n", s / 3600, (s % 3600) / 60, s % 60
    else if (s >= 60) printf "%dm %02ds\n", s / 60, s % 60
    else printf "%d.%01ds\n", s, int(ms % 1000 / 100)
  }'
}

{
  echo "## $TITLE"
  echo
  interval="$(awk -F'\t' '$1 == "sampler" {print $2}' "$dir/notes.tsv" 2>/dev/null | tail -1)"
  stages="$(wc -l < "$stats" | tr -d ' ')"
  # shellcheck disable=SC2016  # the backticks are Markdown, not a subshell
  printf '`%s` across %s stages' "$(fmt_ms "$total_ms")" "$stages"
  [ "$cores" -gt 0 ] && printf ' on %s cores' "$cores"
  [ -n "$interval" ] && printf ', %s' "$interval"
  printf '.\n\n'

  if [ "$sampled" -gt 0 ]; then
    echo "| stage | duration | share | peak cpu | mean cpu | peak mem | cpu shape |"
    echo "| --- | ---: | ---: | ---: | ---: | ---: | --- |"
  else
    echo "| stage | duration | share |"
    echo "| --- | ---: | ---: |"
  fi

  # A second pass formats; keeping it out of the aggregation above is what lets
  # the rows be sorted by a plain `sort` between the two.
  awk -F'\t' -v total="$total_ms" -v cores="$cores" -v sampled="$sampled" '
    function fmt(ms) {
      s = int(ms / 1000)
      if (s >= 3600) return sprintf("%dh %02dm", s / 3600, (s % 3600) / 60)
      if (s >= 60)   return sprintf("%dm %02ds", s / 60, s % 60)
      return sprintf("%ds", s)
    }
    function bytes(kb) {
      b = kb * 1024; split("B KiB MiB GiB TiB", u, " "); i = 1
      while (b >= 1024 && i < 5) { b /= 1024; i++ }
      return sprintf("%.1f %s", b, u[i])
    }
    function spark(codes) {
      out = ""
      for (i = 1; i <= length(codes); i++) {
        c = substr(codes, i, 1)
        if (c == " ") { out = out " "; continue }
        out = out blk[c + 0]
      }
      return out
    }
    BEGIN {
      blk[1] = "▁"; blk[2] = "▂"; blk[3] = "▃"; blk[4] = "▄"
      blk[5] = "▅"; blk[6] = "▆"; blk[7] = "▇"; blk[8] = "█"
    }
    {
      share = (total > 0) ? 100 * $2 / total : 0
      if (sampled > 0) {
        # Effective busy cores alongside the percentage: "62% (5.0 of 8)" says
        # what a bigger runner would and would not have bought.
        peak = ($3 > 0) ? (cores > 0 ? sprintf("%d%% (%.1f of %d)", $3, $3 * cores / 100, cores) : sprintf("%d%%", $3)) : ""
        mean = ($4 > 0) ? sprintf("%d%%", $4 + 0.5) : ""
        # A stage shorter than one sampling interval has no shape; empty
        # backticks would render as a stray code span rather than as a blank.
        shape = (length($6) > 0) ? "`" spark($6) "`" : ""
        printf "| %s | %s | %d%% | %s | %s | %s | %s |\n", $1, fmt($2), share + 0.5, peak, mean, ($5 > 0 ? bytes($5) : ""), shape
      } else {
        printf "| %s | %s | %d%% |\n", $1, fmt($2), share + 0.5
      }
    }
  ' "$sorted"

  if [ "$sampled" -gt 0 ]; then
    echo
    if [ "$cores" -gt 0 ]; then
      echo "CPU is the share of all $cores cores busy, measured per sampling interval from \`/proc/stat\` deltas rather than from a load average, so it attributes to the stage it was spent in."
    else
      echo "CPU is the share of all cores busy, measured per sampling interval from \`/proc/stat\` deltas."
    fi
    echo "A full block in the shape is every core busy for that bucket; a stage that never fills one is waiting on something and will not get faster on a bigger runner."
  fi

  # Notes carry what the durations cannot explain: whether the cache hit, and
  # how big it was. A slow stage with a cold cache is a different finding from
  # a slow stage with a warm one.
  if [ -s "$dir/notes.tsv" ] && grep -q '^cache\.' "$dir/notes.tsv"; then
    echo
    echo "### Cache"
    echo
    echo "| key | value |"
    echo "| --- | --- |"
    grep '^cache\.' "$dir/notes.tsv" | awk -F'\t' '{printf "| `%s` | %s |\n", $1, $2}'
  fi
} > "$dir/report.md"

# Rendered to a file first, then appended. $GITHUB_STEP_SUMMARY is a SEPARATE
# file per step: the runner concatenates each step's file into the job summary,
# so a later step that opens it sees an empty one. Keeping the report on disk is
# what lets a consumer assert on it, diff two runs, or upload it as an artifact,
# none of which the step summary can support.
cat "$dir/report.md" >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

slowest="$(head -1 "${stats}.sorted" 2>/dev/null || sort -t"$(printf '\t')" -k2,2nr "$stats" | head -1)"
{
  echo "report-path=$dir/report.md"
  echo "total-ms=$total_ms"
  echo "total-seconds=$(( total_ms / 1000 ))"
  echo "slowest-stage=$(printf '%s' "$slowest" | cut -f1)"
  echo "slowest-seconds=$(( $(printf '%s' "$slowest" | cut -f2) / 1000 ))"
} >> "${GITHUB_OUTPUT:-/dev/null}"

echo "reported $(wc -l < "$stats" | tr -d ' ') stages, $(fmt_ms "$total_ms") total"
