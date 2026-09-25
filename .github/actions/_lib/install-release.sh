#!/usr/bin/env bash
# Install one binary from a pinned release archive. Source it, then:
#
#   release_target                                   the runner's musl target triple
#   release_sha <sha256-x86_64> <sha256-aarch64>     the pin for the runner's architecture
#   install_release <url> <sha256> <bin> <dest-dir>  downloads, verifies and installs the binary
#
# install_release downloads the .tar.gz to a temporary directory (through
# retry_transient), verifies it against the pinned sha256 before anything is
# extracted, and installs the file named <bin> into <dest-dir>, wherever the
# archive keeps it, so layouts with and without a top-level directory both
# work. A malformed pin, a checksum mismatch or an archive without that file
# prints ::error:: and returns 1; nothing lands in <dest-dir> then.
#
# The static musl builds run on any Linux of their architecture, inside a job
# container too, which is why this installer knows no other target.

# shellcheck source=retry-transient.sh disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/retry-transient.sh"

release_target() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  [ "$os" = Linux ] || {
    echo "::error::pinned releases install on Linux runners only (got $os)" >&2
    return 1
  }
  case "$arch" in
    x86_64) echo x86_64-unknown-linux-musl ;;
    aarch64 | arm64) echo aarch64-unknown-linux-musl ;;
    *)
      echo "::error::no pinned build for architecture $arch" >&2
      return 1
      ;;
  esac
}

release_sha() {
  local target
  target=$(release_target) || return 1
  case "$target" in
    x86_64-*) echo "$1" ;;
    aarch64-*) echo "$2" ;;
  esac
}

install_release() {
  local url="$1" sha="$2" bin="$3" dest="$4" tmp found
  [[ "$sha" =~ ^[a-f0-9]{64}$ ]] || {
    echo "::error::invalid sha256 pin '$sha' for $url" >&2
    return 1
  }
  [[ "$bin" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "::error::invalid binary name '$bin'" >&2
    return 1
  }
  tmp=$(mktemp -d)
  # Download, then verify: the checksum is pinned by the caller, so a moved
  # release asset fails here rather than landing an unexpected binary.
  if ! retry_transient curl --proto '=https' --tlsv1.2 -sSfL "$url" -o "$tmp/archive.tar.gz"; then
    rm -rf "$tmp"
    echo "::error::download failed: $url" >&2
    return 1
  fi
  if ! echo "$sha  $tmp/archive.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
    rm -rf "$tmp"
    echo "::error::sha256 mismatch for $url: the pin is $sha" >&2
    return 1
  fi
  mkdir -p "$tmp/x"
  tar -xzf "$tmp/archive.tar.gz" -C "$tmp/x"
  found=$(find "$tmp/x" -type f -name "$bin" | head -n 1)
  if [ -z "$found" ]; then
    rm -rf "$tmp"
    echo "::error::$url holds no file named $bin" >&2
    return 1
  fi
  mkdir -p "$dest"
  install -m 0755 "$found" "$dest/$bin"
  rm -rf "$tmp"
}
