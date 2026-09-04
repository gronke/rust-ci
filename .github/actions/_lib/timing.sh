#!/usr/bin/env bash
# Shared state for the timing actions (timing-start, timing-mark, timing-report)
# and for the optional cache statistics in rust-cache / rust-cache-save.
# Source it; every function is a no-op-safe append.
#
# Everything lives in one directory under $RUNNER_TEMP, exported as
# RUST_CI_TIMING_DIR so later steps in the same job find it without an input:
#
#   marks.tsv     epoch_ms <TAB> stage name          one line per timing-mark
#   samples.tsv   epoch_ms <TAB> cpu-busy-percent <TAB> mem_used_kb <TAB> mem_total_kb <TAB> disk_avail_kb
#   notes.tsv     key <TAB> value                    facts contributed by other actions
#   sampler.pid   pid of the background resource sampler, when one runs
#
# TSV rather than JSON on purpose: the writers are shell one-liners appending
# under concurrency, and awk reads it in the report without a jq dependency.
# A tab-free field discipline keeps that parse honest, so stage names are
# sanitized on the way in.

# Directory the whole job shares. Resolved rather than required, so a
# timing-mark placed before timing-start still records instead of failing:
# a missing mark is a hole in the report that nothing else would explain.
timing_dir() {
  local dir="${RUST_CI_TIMING_DIR:-${RUNNER_TEMP:-/tmp}/rust-ci-timing}"
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
# stage name reaches this from a workflow input. Collapse both to a space.
timing_sanitize() {
  printf '%s' "$1" | tr '\t\n\r' '   ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# Append a stage boundary. A mark records where a stage BEGINS; its duration is
# the distance to the next mark, which is why timing-report writes a final
# sentinel of its own before rendering.
timing_mark() {
  local dir name
  dir="$(timing_dir)"
  name="$(timing_sanitize "${1:-unnamed}")"
  printf '%s\t%s\n' "$(timing_now_ms)" "$name" >> "$dir/marks.tsv"
}

# Append a free-form fact. Used by rust-cache for hit/miss and restore sizes,
# so the report can say why a run was slow rather than only that it was.
timing_note() {
  local dir key value
  dir="$(timing_dir)"
  key="$(timing_sanitize "${1:-unnamed}")"
  value="$(timing_sanitize "${2:-}")"
  printf '%s\t%s\n' "$key" "$value" >> "$dir/notes.tsv"
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
