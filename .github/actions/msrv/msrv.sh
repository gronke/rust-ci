#!/usr/bin/env bash
# Compile — or test — the crate inside the MSRV image (its toolchain already IS the declared
# MSRV, so a plain `cargo check` is the MSRV check, and `cargo test` extends the floor to
# dev-dependencies and the test suite). PACKAGE / FEATURES (each may be empty) shape the
# command; COMMAND selects check (default) or test. The lockfile is resolved up front by the
# action — the source is mounted read-only here, so the run is always --locked and only reads
# it. OFFLINE=true appends --offline (assumes a prior cargo-fetch + the action's
# --network none). cargo runs in the mounted workdir.
set -euo pipefail

command="${COMMAND:-check}"
case "$command" in
  check | test) ;;
  *)
    echo "::error::msrv: command must be 'check' or 'test', got '$command'"
    exit 1
    ;;
esac

offline_arg=""
if [ "${OFFLINE:-false}" = "true" ]; then offline_arg="--offline"; fi
pkg_arg=""
if [ -n "${PACKAGE:-}" ]; then pkg_arg="-p ${PACKAGE}"; fi

echo "::group::cargo ${command} on MSRV ${MSRV:-?}"
rustc --version
# shellcheck disable=SC2086  # pkg/offline/FEATURES are intentionally word-split (flag or empty)
cargo "$command" $pkg_arg $offline_arg --locked ${FEATURES:-}
echo "::endgroup::"
