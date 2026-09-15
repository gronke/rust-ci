#!/usr/bin/env bash
# Inputs arrive as env vars from action.yml:
#   MODE  auto | on | off
#   URL   explicit mirror URL, overrides RUST_CI_CRATES_MIRROR from the job env
set -euo pipefail

emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

url="${URL:-${RUST_CI_CRATES_MIRROR:-}}"

case "$MODE" in
  off)
    emit active false
    exit 0
    ;;
  on)
    [ -n "$url" ] || {
      echo "::error::crates-mirror: mode 'on' but no mirror URL (url input or RUST_CI_CRATES_MIRROR)"
      exit 1
    }
    ;;
  auto)
    if [ -z "$url" ]; then
      emit active false
      exit 0
    fi
    ;;
  *)
    echo "::error::crates-mirror: invalid mode '$MODE' (auto|on|off)"
    exit 1
    ;;
esac

# Charset check before the value reaches a config file; cargo requires
# sparse index URLs to end in a slash, so a missing one is appended.
url_re='^sparse\+https?://[]A-Za-z0-9._:/[-]{1,512}$'
[[ "$url" =~ $url_re ]] || {
  echo "::error::crates-mirror: mirror URL fails the charset check: $url"
  exit 1
}
case "$url" in */) ;; *) url="$url/" ;; esac

cargo_dir="${CARGO_HOME:-$HOME/.cargo}"
config="$cargo_dir/config.toml"
mkdir -p "$cargo_dir"
if [ -f "$config" ] && grep -q '^\[source\.crates-io\]' "$config"; then
  # Idempotent only when it is OUR replacement pointing at THIS url; any
  # other crates-io replacement is somebody's deliberate configuration.
  if grep -qF 'replace-with = "rust-ci-mirror"' "$config" \
    && grep -qF "registry = \"$url\"" "$config"; then
    emit active true
    echo "crates-mirror: $config already routes crates-io to $url."
    exit 0
  fi
  echo "::error::crates-mirror: $config already replaces crates-io; refusing to fight it"
  exit 1
fi

{
  echo ""
  echo "# crates-mirror (rust-ci): route crates-io through the runner-local mirror."
  echo "# Cargo.lock checksums stay the canonical crates.io hashes, so the mirror"
  echo "# cannot alter what a build consumes."
  echo "[source.crates-io]"
  echo "replace-with = \"rust-ci-mirror\""
  echo ""
  echo "[source.rust-ci-mirror]"
  echo "registry = \"$url\""
} >> "$config"

emit active true
echo "crates-mirror: crates-io routed to $url ($config)."
