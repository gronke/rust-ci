#!/usr/bin/env bash
# fmt / clippy / test for one feature universe. Inputs arrive as env vars from
# action.yml; cargo runs in the step's working-directory.
#   FMT CLIPPY TEST   "true"/"false" toggles
#   FEATURES          feature flag for clippy + test (e.g. --all-features)
#   CLIPPY_ARGS       extra clippy args (before -- -D warnings)
#   TEST_ARGS         extra cargo test args
set -euo pipefail

if [ "$FMT" = "true" ]; then
  echo "::group::cargo fmt"
  cargo fmt --all -- --check
  echo "::endgroup::"
fi

if [ "$CLIPPY" = "true" ]; then
  echo "::group::cargo clippy"
  # shellcheck disable=SC2086  # CLIPPY_ARGS / FEATURES are intentionally split
  cargo clippy --workspace $CLIPPY_ARGS $FEATURES -- -D warnings
  echo "::endgroup::"
fi

if [ "$TEST" = "true" ]; then
  echo "::group::cargo test"
  # shellcheck disable=SC2086  # FEATURES / TEST_ARGS are intentionally split
  cargo test --workspace $FEATURES $TEST_ARGS
  echo "::endgroup::"
fi
