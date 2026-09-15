#!/usr/bin/env bash
# Inputs arrive as env vars from action.yml: (none)
#
# Not -e: statistics must never fail the job.
set -uo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

# Keyed on the wrapper alone, so a consumer who installed sccache another
# way gets the same numbers.
if [ ! -x "${RUSTC_WRAPPER:-/nonexistent}" ] || ! "$RUSTC_WRAPPER" --version 2>/dev/null | grep -q '^sccache '; then
  echo "sccache-stats: sccache is not the RUSTC_WRAPPER; nothing to record."
  exit 0
fi

echo "::group::sccache statistics"
"$RUSTC_WRAPPER" --show-stats || true
echo "::endgroup::"

# The JSON shape is defended with fallbacks: a renamed field yields zeros
# here, never a red job; the raw group above stays the source of truth.
if command -v jq >/dev/null 2>&1; then
  stats=$("$RUSTC_WRAPPER" --show-stats --stats-format=json 2>/dev/null) || stats=""
  if [ -n "$stats" ]; then
    requests=$(jq -r '.stats.compile_requests // 0' <<<"$stats" 2>/dev/null) || requests=0
    hits=$(jq -r '[.stats.cache_hits.counts[]?] | add // 0' <<<"$stats" 2>/dev/null) || hits=0
    misses=$(jq -r '[.stats.cache_misses.counts[]?] | add // 0' <<<"$stats" 2>/dev/null) || misses=0
    errors=$(jq -r '[.stats.cache_errors.counts[]?] | add // 0' <<<"$stats" 2>/dev/null) || errors=0
    timing_note cache.sccache "$hits hits / $misses misses of $requests compile requests"
    if [ "${errors:-0}" != "0" ]; then
      timing_note cache.sccache.errors "$errors"
    fi
  fi
else
  echo "sccache-stats: jq is unavailable; the log group above is the record."
fi

exit 0
