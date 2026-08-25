#!/usr/bin/env bash
# Record what the prune removed, for the timing report's Cache section.
# Inputs arrive as env vars from action.yml:
#   TARGET_DIR             pruned target directory
#   RUST_CI_TARGET_BYTES_IN size before the prune, when rust-cache measured it
#
# The prune ratio is the number that says whether the saved cache is mostly
# dependency artifacts (its purpose) or mostly workspace-member objects that
# every consumer then restores and immediately overwrites.
set -euo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

[ -d "$TARGET_DIR" ] || exit 0

after="$(du -sb "$TARGET_DIR" 2>/dev/null | cut -f1)"
[ -n "$after" ] || exit 0
timing_note "cache.target.pruned" "$(timing_bytes "$after")"

before="${RUST_CI_TARGET_BYTES_IN:-0}"
case "$before" in '' | *[!0-9]*) before=0 ;; esac
# Only meaningful when rust-cache measured the same tree before the build; a
# build that grew target/ between the two reads makes the ratio a lower bound,
# which is why it is labelled as removed-by-prune rather than as a saving.
if [ "$before" -gt 0 ] && [ "$after" -le "$before" ]; then
  timing_note "cache.target.prune_removed" \
    "$(timing_bytes "$(( before - after ))") of $(timing_bytes "$before") ($(( 100 - after * 100 / before ))%)"
fi
