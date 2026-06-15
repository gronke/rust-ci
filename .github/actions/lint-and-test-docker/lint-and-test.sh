#!/usr/bin/env bash
# fmt + clippy + test, sealed: --offline --locked (a cargo-fetch'd cache and a
# committed Cargo.lock are assumed; this runs under --network none). FEATURES
# (may be empty) applies to clippy + test. cargo runs in the mounted workdir.
set -euo pipefail

echo "::group::cargo fmt"
cargo fmt --all -- --check
echo "::endgroup::"

echo "::group::cargo clippy"
# shellcheck disable=SC2086  # FEATURES is intentionally word-split (a flag or empty)
cargo clippy --workspace --all-targets --offline --locked ${FEATURES:-} -- -D warnings
echo "::endgroup::"

echo "::group::cargo test"
# shellcheck disable=SC2086
cargo test --workspace --offline --locked ${FEATURES:-}
echo "::endgroup::"
