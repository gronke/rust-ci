#!/usr/bin/env bash
# Run an installed tool from the shared cargo bin dir. USE_BIN_DIR is /cache/cargo/bin
# in the sealed container and <cargo-cache>/bin on the host; prepend it so the tool
# AND `cargo <subcommand>` (cargo finds cargo-<sub> on PATH) resolve. The same script
# serves both paths so they cannot drift. ARGS is the command line, intentionally
# word-split — the same containment cargo-docker.sh applies to its ARGS.
set -euo pipefail

export PATH="${USE_BIN_DIR:?cargo-use: USE_BIN_DIR required}:$PATH"

# shellcheck disable=SC2086  # ARGS is intentionally word-split (the command line)
exec ${ARGS:?cargo-use: args required (the command line to run)}
