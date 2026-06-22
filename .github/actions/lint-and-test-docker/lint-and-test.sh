#!/usr/bin/env bash
# fmt + clippy + test with --locked. OFFLINE=true (default) appends --offline
# (a cargo-fetch'd cache + a committed Cargo.lock are assumed; the action also
# runs --network none); OFFLINE=false fetches as it builds. FEATURES (may be
# empty) applies to clippy + test. cargo runs in the mounted workdir.
set -euo pipefail

offline_arg=""
if [ "${OFFLINE:-true}" = "true" ]; then offline_arg="--offline"; fi

echo "::group::cargo fmt"
cargo fmt --all -- --check
echo "::endgroup::"

echo "::group::cargo clippy"
# shellcheck disable=SC2086  # offline_arg / FEATURES are intentionally word-split
cargo clippy --workspace --all-targets $offline_arg --locked ${FEATURES:-} -- -D warnings
echo "::endgroup::"

echo "::group::cargo test"
# shellcheck disable=SC2086
cargo test --workspace $offline_arg --locked ${FEATURES:-}
echo "::endgroup::"
