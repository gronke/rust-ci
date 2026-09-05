#!/usr/bin/env bash
# Initialise the timing state and start the resource sampler.
# Inputs arrive as env vars from action.yml:
#   SAMPLE_INTERVAL   seconds between resource samples ("0" disables sampling)
#   FIRST_STAGE       name for the interval that starts here
set -euo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

dir="$(timing_dir)"
# Re-running timing-start in one job would otherwise interleave two mark
# sequences into one file and every duration after the overlap would be
# nonsense. Start clean and say so.
if [ -s "$dir/marks.tsv" ]; then
  echo "::warning title=timing-start ran twice::discarding $(wc -l < "$dir/marks.tsv") earlier marks; only the last timing-start in a job is measured"
fi
: > "$dir/marks.tsv"
: > "$dir/samples.tsv"
: > "$dir/notes.tsv"
# Derived files from an earlier report in the same job would otherwise be read
# as this run's when picking the slowest stage.
rm -f "$dir/stages.tsv" "$dir/stages.tsv.sorted"

echo "RUST_CI_TIMING_DIR=$dir" >> "$GITHUB_ENV"

cores="$(nproc 2>/dev/null || echo 0)"
timing_note "runner.cores" "$cores"
timing_note "runner.os" "${RUNNER_OS:-unknown}"

# Sampling reads /proc, so it is Linux-only. Say so rather than silently
# producing a report with empty load columns, which reads as "no load".
if [ "$SAMPLE_INTERVAL" = "0" ]; then
  timing_note "sampler" "sampling disabled by input"
elif [ ! -r /proc/stat ] || [ ! -r /proc/meminfo ]; then
  timing_note "sampler" "sampling unavailable (no /proc on ${RUNNER_OS:-this runner})"
  echo "resource sampling unavailable on ${RUNNER_OS:-this runner}; durations only"
else
  timing_note "sampler" "sampling every ${SAMPLE_INTERVAL}s"
  # nohup + a redirect off the step's stdout is what lets this outlive the
  # step: the runner closes the step's pipes when the step ends, and a
  # sampler still writing to them would die on SIGPIPE at the first tick of
  # the next stage, which is exactly the data the report needs.
  rm -f "$dir/sampler.pid"
  nohup setsid bash "$GITHUB_ACTION_PATH/sampler.sh" \
    "$dir/samples.tsv" "$SAMPLE_INTERVAL" "$dir/sampler.pid" \
    > "$dir/sampler.log" 2>&1 &
  disown 2>/dev/null || true
  # The sampler writes its own pid: $! here is nohup's, and setsid forks again
  # on top of that, so neither is the process timing-report has to stop.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$dir/sampler.pid" ] && break
    sleep 0.2
  done
  if [ -s "$dir/sampler.pid" ]; then
    echo "resource sampler started (pid $(cat "$dir/sampler.pid"), every ${SAMPLE_INTERVAL}s)"
  else
    echo "::warning title=Sampler did not report in::resource sampling may be missing from the report"
  fi
fi

# An empty first-stage starts the sampler without laying down a mark. With no marks in
# the file, timing-report derives the stage boundaries from the Actions API instead, so
# the resource sampler and the per-step API timings combine with no manual timing-mark steps.
if [ -n "$FIRST_STAGE" ]; then
  timing_mark "$FIRST_STAGE"
fi
echo "timing state at $dir"
echo "timing-dir=$dir" >> "$GITHUB_OUTPUT"
