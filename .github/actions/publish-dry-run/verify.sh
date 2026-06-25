#!/usr/bin/env bash
# Sealed verify-build: `cargo package` builds the packaged crate with --offline and
# the action runs it under --network=none, so the dependency build.rs / proc-macros
# it compiles and executes cannot reach the network. (`cargo publish --dry-run` is
# not usable here — it always contacts the registry, which --offline rejects; the
# publish/registry checks run networked-but-build-free in the prep step instead.)
# Reads the package name + publishability prepared by the networked prep step.
set -euo pipefail

marker="${CARGO_TARGET_DIR:-target}/.cicd-publish-dry-run"
if [ ! -f "$marker" ]; then
  echo "::error::missing $marker — the networked prep step did not run"
  exit 1
fi
IFS=$'\t' read -r NAME PUBLISHABLE < "$marker"

if [ "$PUBLISHABLE" != "true" ]; then
  echo "::notice::publish = false — internal crate; skipping the sealed verify-build"
  exit 0
fi

echo "::group::cargo package (sealed verify-build: --network none + --offline)"
cargo package --offline --locked -p "$NAME"
echo "::endgroup::"
echo "✓ sealed verify-build passed for $NAME"
