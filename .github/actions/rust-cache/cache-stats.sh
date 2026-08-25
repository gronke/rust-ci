#!/usr/bin/env bash
# Record what the restore actually delivered, for the timing report's Cache
# section. Inputs arrive as env vars from action.yml:
#   TARGET_DIR   restored target directory ("" when cache-target is off)
#   TARGET_HIT   actions/cache "cache-hit": "true" on an exact key match
#   TARGET_KEY   the exact key the restore asked for
#   REGISTRY_DIRS newline-separated registry paths
#
# The distinction this exists to make: a cache that restores but whose
# artifacts are not reusable reports success at every step, every suite still
# passes, and the job is simply minutes more expensive with nothing saying so.
# The size and the hit kind together are what separate "cold" from "warm but
# stale", which a build log alone cannot.
set -euo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

# An exact hit and a restore-key fallback are both "restored" to actions/cache
# but mean opposite things for a build: the fallback carries another
# generation's artifacts, which cargo may or may not accept.
if [ -n "$TARGET_DIR" ]; then
  # shellcheck disable=SC2153  # TARGET_HIT arrives from action.yml's env block
  if [ "$TARGET_HIT" = "true" ]; then
    timing_note "cache.target" "exact hit"
  elif [ -d "$TARGET_DIR" ]; then
    timing_note "cache.target" "restore-key fallback (another generation)"
  else
    timing_note "cache.target" "miss"
  fi
  timing_note "cache.target.key" "$TARGET_KEY"
  if [ -d "$TARGET_DIR" ]; then
    bytes="$(du -sb "$TARGET_DIR" 2>/dev/null | cut -f1)"
    [ -n "$bytes" ] && timing_note "cache.target.restored" "$(timing_bytes "$bytes")"
    # Handed to rust-cache-save so it can report the prune ratio without
    # re-walking a multi-gigabyte tree a second time.
    echo "RUST_CI_TARGET_BYTES_IN=${bytes:-0}" >> "$GITHUB_ENV"
  fi
fi

reg=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -d "$d" ] || continue
  n="$(du -sb "$d" 2>/dev/null | cut -f1)" || n=0
  reg=$(( reg + ${n:-0} ))
done <<< "$REGISTRY_DIRS"
[ "$reg" -gt 0 ] && timing_note "cache.registry.restored" "$(timing_bytes "$reg")"
