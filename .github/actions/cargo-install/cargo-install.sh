#!/usr/bin/env bash
# Install TOOL into $CARGO_HOME/bin. In the sealed container CARGO_HOME=/cache/cargo
# (the shared, host-mounted dir set by seal.sh); in host mode the action exports
# CARGO_HOME to the same host dir. The same script serves both paths so they cannot
# drift. TOOL/VERSION are pre-validated by the action and passed as QUOTED argv here
# (no word-split, no glob); only the free-form ARGS is intentionally word-split, the
# same containment cargo-docker.sh applies to its ARGS.
set -euo pipefail

install_args=(install "$TOOL")
[ -n "${VERSION:-}" ] && install_args+=(--version "$VERSION")
[ "${LOCKED:-true}" = "true" ] && install_args+=(--locked)

# shellcheck disable=SC2086  # ARGS is intentionally word-split (free-form flags)
exec cargo "${install_args[@]}" ${ARGS:-}
