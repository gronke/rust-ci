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
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      # Windows runners — notably windows-11-arm — can ship no Rust at all, and the Unix
      # sh.rustup.rs installer doesn't apply here. Fetch the arch-appropriate rustup-init.exe.
      # git-bash's `uname -m` can't be trusted under x64 emulation, so read the true machine arch
      # from Windows' own PROCESSOR_ARCHITE(W6432) variables.
      winarch="${PROCESSOR_ARCHITEW6432:-${PROCESSOR_ARCHITECTURE:-$(uname -m)}}"
      case "$winarch" in
        ARM64 | arm64 | aarch64) host=aarch64-pc-windows-msvc ;;
        *) host=x86_64-pc-windows-msvc ;;
      esac
      curl --proto '=https' --tlsv1.2 -sSfL \
        "https://static.rust-lang.org/rustup/dist/$host/rustup-init.exe" -o rustup-init.exe
      ./rustup-init.exe -y --default-toolchain "$TOOLCHAIN" --profile minimal --no-modify-path
      # GITHUB_PATH wants a Windows path (later steps may run in pwsh); this script continues in
      # git-bash, where the cargo bin dir is $HOME/.cargo/bin.
      printf '%s\\.cargo\\bin\n' "${USERPROFILE:-$HOME}" >> "$GITHUB_PATH"
      export PATH="$HOME/.cargo/bin:$PATH"
      ;;
    *)
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain "$TOOLCHAIN" --profile minimal --no-modify-path
      echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"
      export PATH="$HOME/.cargo/bin:$PATH"
      ;;
  esac
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
