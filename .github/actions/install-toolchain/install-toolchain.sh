#!/usr/bin/env bash
# Install a Rust toolchain via rustup. Inputs arrive as env vars from action.yml:
#   TOOLCHAIN   toolchain to install / default (e.g. stable, 1.77.2)
#   COMPONENTS  space-separated rustup components (e.g. "rustfmt clippy")
#   TARGETS     space-separated rustup targets
set -euo pipefail

if command -v rustup >/dev/null 2>&1; then
  rustup toolchain install "$TOOLCHAIN" --profile minimal
  rustup default "$TOOLCHAIN"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain "$TOOLCHAIN" --profile minimal --no-modify-path
  echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"
  export PATH="$HOME/.cargo/bin:$PATH"
fi

if [ -n "$COMPONENTS" ]; then
  # shellcheck disable=SC2086  # word-splitting is intended for the component list
  rustup component add $COMPONENTS
fi
if [ -n "$TARGETS" ]; then
  # shellcheck disable=SC2086  # word-splitting is intended for the target list
  rustup target add $TARGETS
fi

rustc --version
cargo --version
