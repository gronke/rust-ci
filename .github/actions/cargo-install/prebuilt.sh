#!/usr/bin/env bash
# Install a tool's binary from a pinned release archive instead of compiling
# it. Runs on the runner in both modes: the static musl binary lands in the
# shared cache's bin/, where a sealed cargo-use finds it too. Inputs arrive as
# env vars from action.yml:
#   BIN             binary name inside the archive
#   VERSION         exact version; fills {version} and is what "present" means
#   URL             release archive URL with {version} and {target} placeholders
#   SHA256_X86_64   pin of the x86_64-unknown-linux-musl archive
#   SHA256_AARCH64  pin of the aarch64-unknown-linux-musl archive
#   BIN_DIR         <cargo-cache>/bin
#   ON_HOST         "true" in host mode, where the tool runs on the runner
# Output: installed ("false" when that exact version was present already).
set -euo pipefail

# shellcheck source=../_lib/install-release.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/install-release.sh"
# shellcheck source=present.sh disable=SC1091
source "$GITHUB_ACTION_PATH/present.sh"

emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

# Named once, so a missing input fails here rather than halfway through.
BIN="${BIN:?}" VERSION="${VERSION:?}" URL="${URL:?}" BIN_DIR="${BIN_DIR:?}" ON_HOST="${ON_HOST:-false}"
SHA256_X86_64="${SHA256_X86_64:?}" SHA256_AARCH64="${SHA256_AARCH64:?}"

# Host mode skips an exact version that later steps would run already. In
# docker mode the cache is writable from sealed steps, so nothing in it runs
# on the runner: the pinned release is installed every time, which also
# replaces whatever a sealed step left under the binary's name.
if [ "$ON_HOST" = true ] && found=$(tool_found "$BIN" "$VERSION" "$BIN_DIR"); then
  echo "cargo-install: $BIN $VERSION is present at $found; nothing to install."
  emit installed false
  exit 0
fi
# A sealed step can swap the directory for a link that points the copy below
# elsewhere on the runner.
if [ -L "$BIN_DIR" ]; then
  echo "::error::cargo-install: $BIN_DIR is a symbolic link, which a sealed step can plant; nothing is installed through it"
  exit 1
fi

target=$(release_target) || exit 1
sha=$(release_sha "$SHA256_X86_64" "$SHA256_AARCH64")
url="${URL//\{version\}/$VERSION}"
url="${url//\{target\}/$target}"
# The pin covers the archive's bytes, not the version it claims to hold, so
# the version check runs on the verified copy in a directory of its own
# before anything lands in the cache.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
install_release "$url" "$sha" "$BIN" "$stage" || exit 1
tool_present "$stage/$BIN" "$VERSION" || {
  echo "::error::cargo-install: $url holds a $BIN that does not report version $VERSION"
  exit 1
}
mkdir -p "$BIN_DIR"
install -m 0755 "$stage/$BIN" "$BIN_DIR/$BIN"
echo "cargo-install: $BIN $VERSION installed from $url"
emit installed true
