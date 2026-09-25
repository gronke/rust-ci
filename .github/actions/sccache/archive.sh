#!/usr/bin/env bash
# Decide whether the job's local disk cache travels as a GitHub Actions cache
# archive: only when the action is not off, `archive` names one, and no
# backend is configured, which wins. Inputs arrive as env vars from
# action.yml:
#   MODE          auto | on | off
#   ARCHIVE       the archive's name ("" for none)
#   ARCHIVE_SIZE  SCCACHE_CACHE_SIZE for the archived directory, unless the job sets one
#   NAMESPACE     the action's namespace ("" for none)
# Outputs: archive ("true"/"false"); once it engages, dir, family (the archive
# name, with the namespace below it), rust (the toolchain hash) and cargo-env
# (the hash of the job's CARGO_* variables), which key the entry.
set -euo pipefail

# shellcheck source=../_lib/sccache-backend.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/sccache-backend.sh"

MODE="${MODE:-auto}"
emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

case "$MODE" in
  auto | on | off) ;;
  gha)
    echo "::error::sccache: mode gha is gone; name an archive, which carries the cache on GitHub's cache service without a host backend"
    exit 1
    ;;
  *)
    echo "::error::sccache: invalid mode '$MODE' (auto|on|off)"
    exit 1
    ;;
esac

if [ -z "${ARCHIVE:-}" ] || [ "$MODE" = off ]; then
  emit archive false
  exit 0
fi
[[ "$ARCHIVE" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "::error::sccache: archive '$ARCHIVE' is not a name of [A-Za-z0-9._-]"
  exit 1
}
# sccache's parse_size takes the unit in either case.
[[ "${ARCHIVE_SIZE:-}" =~ ^[0-9]+[KMGTkmgt]?$ ]] || {
  echo "::error::sccache: archive-size '${ARCHIVE_SIZE:-}' is not a size such as 2G or 500M"
  exit 1
}
read -r kind _ <<<"$(sccache_backend)"
if [ -n "${kind:-}" ]; then
  echo "sccache: the configured $kind backend serves this job; the archive '$ARCHIVE' stays unused."
  emit archive false
  exit 0
fi

# The namespace joins the key, so jobs sharing an archive name under
# different namespaces are separate families instead of rivals for one entry.
family="$ARCHIVE"
if [ -n "${NAMESPACE:-}" ]; then
  sccache_namespace_valid "$NAMESPACE" || exit 1
  family="$ARCHIVE/$NAMESPACE"
fi

# The toolchain goes into the key: a rustc bump starts from an empty directory
# instead of restoring objects no compile can hit. A rustc that gives no
# version, missing or a rustup shim without a toolchain, keys as norustc.
rust=norustc
if version=$(rustc -V 2>/dev/null); then
  rust=$(printf '%s\n' "$version" | sha256sum | cut -c1-12)
fi

# sccache hashes the job's CARGO_* variables into every object's key, all but
# the four skipped below, so the key carries a hash of the same set: a job
# whose environment differs keys an entry of its own instead of restoring
# objects it cannot hit. An unset CARGO_INCREMENTAL counts as the 0 that
# sccache.sh exports.
cargo_env=$(
  export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-0}"
  for name in $(compgen -e | LC_ALL=C sort); do
    case "$name" in
      CARGO_MAKEFLAGS | CARGO_BUILD_JOBS | CARGO_ENCODED_RUSTFLAGS | CARGO_REGISTRIES_*) ;;
      CARGO_*) printf '%s=%s\0' "$name" "${!name}" ;;
    esac
  done | sha256sum | cut -c1-12
)

dir="${RUNNER_TEMP:-/tmp}/rust-ci-sccache/cache"
mkdir -p "$dir"
{
  echo "SCCACHE_DIR=$dir"
  [ -n "${SCCACHE_CACHE_SIZE:-}" ] || echo "SCCACHE_CACHE_SIZE=$ARCHIVE_SIZE"
} >> "$GITHUB_ENV"
emit archive true
emit dir "$dir"
emit family "$family"
emit rust "$rust"
emit cargo-env "$cargo_env"
echo "sccache: the local cache $dir travels as the GitHub Actions cache archive '$family'."
