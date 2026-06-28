#!/usr/bin/env bash
# Compile the crate inside the MSRV image (its toolchain already IS the declared
# MSRV, so a plain `cargo check` is the MSRV check). PACKAGE / FEATURES / LOCKED
# (each may be empty) shape the command. OFFLINE=true appends --offline (assumes a
# prior cargo-fetch + the action's --network none); the default fetches as it
# resolves, so a newer dependency within range surfaces here. cargo runs in the
# mounted workdir.
set -euo pipefail

offline_arg=""
if [ "${OFFLINE:-false}" = "true" ]; then offline_arg="--offline"; fi
locked_arg=""
if [ "${LOCKED:-false}" = "true" ]; then locked_arg="--locked"; fi
pkg_arg=""
if [ -n "${PACKAGE:-}" ]; then pkg_arg="-p ${PACKAGE}"; fi

echo "::group::cargo check on MSRV ${MSRV:-?}"
rustc --version
# shellcheck disable=SC2086  # pkg/offline/locked/FEATURES are intentionally word-split (flag or empty)
cargo check $pkg_arg $offline_arg $locked_arg ${FEATURES:-}
echo "::endgroup::"
