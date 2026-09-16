#!/usr/bin/env bash
# fmt / clippy / test for one feature universe. Inputs arrive as env vars: from
# action.yml when the lint-and-test action runs it natively, through the sealed
# container's env-file when lint-and-test-docker runs it (that action fixes
# FMT/CLIPPY/TEST=true, CLIPPY_ARGS=--all-targets, LOCKED=true and hands over
# its offline and features inputs). cargo runs in the current directory.
#   FMT CLIPPY TEST   "true"/"false" toggles (unset counts as true)
#   FEATURES          feature flag for clippy + test (e.g. --all-features)
#   CLIPPY_ARGS       extra clippy args (before -- -D warnings)
#   TEST_ARGS         extra cargo test args
#   OFFLINE           "true" adds --offline to clippy + test (unset counts as false)
#   LOCKED            "true" adds --locked to clippy + test (unset counts as false)
set -euo pipefail

offline_arg=""
[ "${OFFLINE:-false}" = "true" ] && offline_arg="--offline"
locked_arg=""
[ "${LOCKED:-false}" = "true" ] && locked_arg="--locked"

if [ "${FMT:-true}" = "true" ]; then
  echo "::group::cargo fmt"
  cargo fmt --all -- --check
  echo "::endgroup::"
fi

if [ "${CLIPPY:-true}" = "true" ]; then
  echo "::group::cargo clippy"
  # shellcheck disable=SC2086  # CLIPPY_ARGS / offline_arg / locked_arg / FEATURES are intentionally split
  cargo clippy --workspace ${CLIPPY_ARGS:-} $offline_arg $locked_arg ${FEATURES:-} -- -D warnings
  echo "::endgroup::"
fi

if [ "${TEST:-true}" = "true" ]; then
  echo "::group::cargo test"
  # shellcheck disable=SC2086  # offline_arg / locked_arg / FEATURES / TEST_ARGS are intentionally split
  cargo test --workspace $offline_arg $locked_arg ${FEATURES:-} ${TEST_ARGS:-}
  echo "::endgroup::"
fi
