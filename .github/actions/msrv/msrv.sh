#!/usr/bin/env bash
# Compile the crate inside the MSRV image (its toolchain already IS the declared MSRV, so a
# plain `cargo check` is the MSRV check). PACKAGE / FEATURES (each may be empty) shape the
# command. The lockfile is resolved up front by the action — the source is mounted read-only
# here, so the check always runs --locked and only reads it. OFFLINE=true appends --offline
# (assumes a prior cargo-fetch + the action's --network none). cargo runs in the mounted workdir.
set -euo pipefail

offline_arg=""
if [ "${OFFLINE:-false}" = "true" ]; then offline_arg="--offline"; fi
pkg_arg=""
if [ -n "${PACKAGE:-}" ]; then pkg_arg="-p ${PACKAGE}"; fi

echo "::group::cargo check on MSRV ${MSRV:-?}"
rustc --version
# shellcheck disable=SC2086  # pkg/offline/FEATURES are intentionally word-split (flag or empty)
cargo check $pkg_arg $offline_arg --locked ${FEATURES:-}
echo "::endgroup::"
