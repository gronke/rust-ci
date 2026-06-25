#!/usr/bin/env bash
# Run one cargo command inside the sealed container. ARGS is the cargo command +
# flags (e.g. "build --release --locked --features full"); when OFFLINE=true,
# --offline is appended (a cargo-fetch'd cache + a committed Cargo.lock are
# assumed, and the action also runs --network none). Do NOT put --offline in ARGS.
set -euo pipefail

offline_arg=""
[ "${OFFLINE:-true}" = "true" ] && offline_arg="--offline"

# shellcheck disable=SC2086  # ARGS / offline_arg are intentionally word-split
exec cargo ${ARGS:-} $offline_arg
