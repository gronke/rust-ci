#!/usr/bin/env bash
# Shared state for timing-start and timing-report and for the cache statistics
# in rust-cache, rust-cache-save and sccache-stats. Source it; every function is
# a no-op-safe append.
#
# Everything lives in $RUNNER_TEMP/rust-ci-timing, the one place every step of
# a job resolves without an input or an exported variable:
#
#   samples.tsv     epoch_ms <TAB> cpu-busy-percent <TAB> mem_used_kb <TAB> mem_total_kb <TAB> disk_avail_kb
#   notes.tsv       key <TAB> value            facts contributed by the actions
#   sampler.pid     pid of the background resource sampler, when one runs
#   boundaries.tsv  epoch_ms <TAB> stage name  stage bounds the report derived
#
# TSV rather than JSON on purpose: the writers are shell one-liners appending
# under concurrency, and awk reads it in the report without a jq dependency.
# A tab-free field discipline keeps that parse honest, so keys and values are
# sanitized on the way in.

timing_dir() {
  local dir="${RUNNER_TEMP:-/tmp}/rust-ci-timing"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# Milliseconds where the platform's date supports it, seconds*1000 otherwise.
# BSD date prints "%3N" literally rather than failing, so the result is
# validated as digits instead of trusting the exit status.
timing_now_ms() {
  local n
  n="$(date +%s%3N 2>/dev/null || true)"
  case "$n" in
    '' | *[!0-9]*) printf '%s\n' "$(( $(date +%s) * 1000 ))" ;;
    *) printf '%s\n' "$n" ;;
  esac
}

# Tabs and newlines would desynchronize every later awk field split, and a
# value can reach this from a workflow input. Collapse both to a space.
timing_sanitize() {
  printf '%s' "$1" | tr '\t\n\r' '   ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# Append a fact. rust-cache notes hit kind and restored sizes, sccache-stats
# its hit counts, so the report can say why a run was slow rather than only
# that it was. The same row is kept for timing_summary below.
timing_note() {
  local dir key value
  dir="$(timing_dir)"
  key="$(timing_sanitize "${1:-unnamed}")"
  value="$(timing_sanitize "${2:-}")"
  printf '%s\t%s\n' "$key" "$value" >> "$dir/notes.tsv"
  _timing_rows="${_timing_rows:-}| \`$key\` | $value |"$'\n'
}

# Append the facts noted so far as a table to the step summary, under the given
# heading, so a consumer without timing-report still sees them. Nothing noted,
# or no summary file (outside Actions), appends nothing; a failed write is not
# an error, statistics never fail a job.
timing_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -n "${_timing_rows:-}" ] || return 0
  printf '### %s\n\n| key | value |\n| --- | --- |\n%s\n' "${1:-Cache}" "$_timing_rows" \
    2>/dev/null >> "$GITHUB_STEP_SUMMARY" || true
}

# Human-readable byte count for the summary tables.
timing_bytes() {
  awk -v b="${1:-0}" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i]
  }'
}
