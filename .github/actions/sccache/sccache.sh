#!/usr/bin/env bash
# Inputs arrive as env vars from action.yml:
#   MODE            auto | on | off
#   VERSION         sccache release (X.Y.Z, no v prefix)
#   SHA256_X86_64   pinned archive checksum, x86_64-unknown-linux-musl
#   SHA256_AARCH64  pinned archive checksum, aarch64-unknown-linux-musl
set -euo pipefail

# shellcheck source=../_lib/retry-transient.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/retry-transient.sh"

emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

# The host's offer sits beside the work directory, the same channel as
# rust-cache's .rust-ci-local-target marker: the work tree is mounted into
# job containers, the runner's own env is not.
work=""
[ -n "${RUNNER_WORKSPACE:-}" ] && work="$(dirname "$RUNNER_WORKSPACE")"
env_file=""
[ -n "$work" ] && [ -f "$work/.rust-ci-env" ] && env_file="$work/.rust-ci-env"

active=false
case "$MODE" in
  off) ;;
  on|gha) active=true ;;
  auto)
    if [ "${RUST_CI_SCCACHE:-}" = "1" ]; then
      active=true
    elif [ -n "$env_file" ] && grep -q '^SCCACHE_' "$env_file"; then
      active=true
    fi
    ;;
  *)
    echo "::error::sccache: invalid mode '$MODE' (auto|on|off|gha)"
    exit 1
    ;;
esac
if [ "$active" != true ]; then
  emit active false
  emit bin ""
  exit 0
fi

# gha: GitHub's cache service is the backend; the host file is ignored. The
# runtime endpoint and token come from the github-script step before this
# one; absent here means that step failed or was skipped.
if [ "$MODE" = "gha" ]; then
  env_file=""
  { [ -n "${ACTIONS_RESULTS_URL:-}" ] && [ -n "${ACTIONS_RUNTIME_TOKEN:-}" ]; } || {
    echo "::error::sccache: gha mode without the cache-service runtime (ACTIONS_RESULTS_URL / ACTIONS_RUNTIME_TOKEN)"
    exit 1
  }
  echo "SCCACHE_GHA_ENABLED=true" >> "$GITHUB_ENV"
  export SCCACHE_GHA_ENABLED=true
fi

# Import the host's SCCACHE_* lines. Keys are allowlisted and values
# charset-checked BEFORE anything reaches $GITHUB_ENV: the file is
# host-owned, but a malformed line must fail loudly here rather than write a
# stray environment line. Line-based reading makes a newline in a value
# impossible by construction; the printable-only check rejects the rest.
key_re='^SCCACHE_[A-Z0-9_]{1,64}$'
val_re='^[[:print:]]{0,2048}$'
imported=0
if [ -n "$env_file" ]; then
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in ''|'#'*) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    if [ "$key" = "$line" ]; then
      echo "::error::sccache: $env_file line $lineno is not KEY=VALUE"
      exit 1
    fi
    # Other consumers' keys (e.g. the crates-mirror URL) are not ours to import.
    case "$key" in RUST_CI_*) continue ;; esac
    [[ "$key" =~ $key_re ]] || {
      echo "::error::sccache: $env_file line $lineno: key '$key' is not an SCCACHE_* name"
      exit 1
    }
    [[ "$val" =~ $val_re ]] || {
      echo "::error::sccache: $env_file line $lineno: value of $key fails the charset check"
      exit 1
    }
    case "$key" in
      *PASSWORD*|*TOKEN*|*SECRET*|*ACCESS_KEY*) echo "::add-mask::$val" ;;
    esac
    echo "$key=$val" >> "$GITHUB_ENV"
    export "$key=$val"
    imported=$((imported + 1))
  done < "$env_file"
fi
if [ "$imported" -eq 0 ] && ! env | grep -q '^SCCACHE_'; then
  echo "::warning title=sccache without a backend::No SCCACHE_* configuration found; sccache falls back to its local-disk default, which an ephemeral runner throws away."
fi

os=$(uname -s)
arch=$(uname -m)
[ "$os" = "Linux" ] || {
  echo "::error::sccache: only Linux runners are supported (got $os)"
  exit 1
}
case "$arch" in
  x86_64) triple=x86_64-unknown-linux-musl sha="$SHA256_X86_64" ;;
  aarch64|arm64) triple=aarch64-unknown-linux-musl sha="$SHA256_AARCH64" ;;
  *)
    echo "::error::sccache: no pinned build for architecture $arch"
    exit 1
    ;;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "::error::sccache: invalid version '$VERSION'"
  exit 1
}
[[ "$sha" =~ ^[a-f0-9]{64}$ ]] || {
  echo "::error::sccache: invalid sha256 pin for $triple"
  exit 1
}

# Static musl build under RUNNER_TEMP: inside a job container that is the
# bind-mounted _work/_temp, so the absolute RUSTC_WRAPPER path below stays
# valid for every later step without touching PATH.
dir="${RUNNER_TEMP:-/tmp}/rust-ci-sccache"
bin="$dir/sccache"
if [ ! -x "$bin" ]; then
  mkdir -p "$dir"
  archive="$dir/sccache.tar.gz"
  url="https://github.com/mozilla/sccache/releases/download/v${VERSION}/sccache-v${VERSION}-${triple}.tar.gz"
  # Download-then-verify: the checksum is pinned in the action, so a moved
  # release asset fails here rather than landing an unexpected binary.
  retry_transient curl --proto '=https' --tlsv1.2 -sSfL "$url" -o "$archive"
  echo "$sha  $archive" | sha256sum -c - >/dev/null
  tar -xzf "$archive" -C "$dir" --strip-components=1 "sccache-v${VERSION}-${triple}/sccache"
  rm -f "$archive"
fi

{
  echo "RUSTC_WRAPPER=$bin"
  echo "RUST_CI_SCCACHE=1"
} >> "$GITHUB_ENV"
# Incremental compiles are uncacheable for sccache; default it off like
# rust-cache does, while obeying an explicit consumer value.
if [ -z "${CARGO_INCREMENTAL:-}" ]; then echo "CARGO_INCREMENTAL=0" >> "$GITHUB_ENV"; fi

# Start the server now so a broken install fails THIS step loudly instead of
# the first compile; backend reachability still proves itself on first use,
# because sccache connects lazily.
"$bin" --start-server >/dev/null 2>&1 || {
  echo "::error::sccache: the server did not start"
  exit 1
}

emit active true
emit bin "$bin"
if [ "$MODE" = "gha" ]; then
  echo "sccache: v$VERSION as RUSTC_WRAPPER (backend: the GitHub cache service)."
else
  echo "sccache: v$VERSION as RUSTC_WRAPPER ($imported key(s) imported from ${env_file:-the job env})."
fi
