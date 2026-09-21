#!/usr/bin/env bash
# Inputs arrive as env vars from action.yml:
#   MODE            auto | on | off | gha
#   NAMESPACE       path below the backend's key prefix ("" for none)
#   VERSION         sccache release (X.Y.Z, no v prefix)
#   STARTUP_TIMEOUT_MS  server_startup_timeout_ms for sccache's configuration file
#   SHA256_X86_64   pinned archive checksum, x86_64-unknown-linux-musl
#   SHA256_AARCH64  pinned archive checksum, aarch64-unknown-linux-musl
set -euo pipefail

# shellcheck source=../_lib/retry-transient.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/retry-transient.sh"

emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

# The backend is whatever SCCACHE_* the job environment carries; sccache reads
# it itself. A present-but-empty variable (an unset `vars.*` expression) does
# not count as a backend.
backend_configured() { env | grep -Eq '^SCCACHE_[A-Za-z0-9_]+=.+'; }

active=false
case "$MODE" in
  off) ;;
  on|gha) active=true ;;
  auto) backend_configured && active=true ;;
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

if [ "$MODE" = "gha" ]; then
  # The runtime endpoint and token come from the github-script step before
  # this one; absent here means that step failed or was skipped.
  { [ -n "${ACTIONS_RESULTS_URL:-}" ] && [ -n "${ACTIONS_RUNTIME_TOKEN:-}" ]; } || {
    echo "::error::sccache: gha mode without the cache-service runtime (ACTIONS_RESULTS_URL / ACTIONS_RUNTIME_TOKEN)"
    exit 1
  }
  echo "SCCACHE_GHA_ENABLED=true" >> "$GITHUB_ENV"
  export SCCACHE_GHA_ENABLED=true
else
  # The gha backend needs the runtime export only `mode: gha` performs; a bare
  # SCCACHE_GHA_ENABLED would fail at the first compile instead of here.
  case "${SCCACHE_GHA_ENABLED:-}" in
    ''|0|false|off) ;;
    *)
      [ -n "${ACTIONS_RESULTS_URL:-}" ] || {
        echo "::error::sccache: SCCACHE_GHA_ENABLED is set but the cache-service runtime is not exported; use mode: gha"
        exit 1
      }
      ;;
  esac
  backend_configured || echo "::warning title=sccache without a backend::No SCCACHE_* configuration found; sccache falls back to its local-disk default, which an ephemeral runner throws away."
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
[[ "$STARTUP_TIMEOUT_MS" =~ ^[0-9]{1,7}$ ]] || {
  echo "::error::sccache: server-startup-timeout-ms must be a number of milliseconds (got '$STARTUP_TIMEOUT_MS')"
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

echo "RUSTC_WRAPPER=$bin" >> "$GITHUB_ENV"
# Incremental compiles are uncacheable for sccache; default it off like
# rust-cache does, while obeying an explicit consumer value.
if [ -z "${CARGO_INCREMENTAL:-}" ]; then echo "CARGO_INCREMENTAL=0" >> "$GITHUB_ENV"; fi

# The client waits for the server, which checks its storage before it
# answers; sccache's ten-second default is short for a remote backend busy
# with other jobs' servers. The wait is sccache's own setting, so it goes into
# its configuration file, exported for every later client in the job too. A
# job that brings its own SCCACHE_CONF, or a default file, keeps it.
if [ -z "${SCCACHE_CONF:-}" ] && [ ! -f "${HOME:-/nonexistent}/.config/sccache/config" ]; then
  conf="$dir/config.toml"
  printf 'server_startup_timeout_ms = %s\n' "$STARTUP_TIMEOUT_MS" > "$conf"
  echo "SCCACHE_CONF=$conf" >> "$GITHUB_ENV"
  export SCCACHE_CONF="$conf"
fi

# A namespace puts this job's objects below the backend's key prefix
# (_lib/sccache-namespace.sh): exported for the server started below, and
# written to $GITHUB_ENV for every compile after this step.
if [ -n "${NAMESPACE:-}" ]; then
  # shellcheck source=../_lib/sccache-namespace.sh disable=SC1091
  source "$GITHUB_ACTION_PATH/../_lib/sccache-namespace.sh"
  namespaced=$(sccache_namespace_env "$NAMESPACE" "$MODE") || exit $?
  if [ -n "$namespaced" ]; then
    printf '%s\n' "$namespaced" >> "$GITHUB_ENV"
    # shellcheck disable=SC2163  # the NAME=VALUE line is the export
    export "$namespaced"
    echo "sccache: namespace $NAMESPACE (${namespaced%%=*})"
  else
    echo "::warning title=sccache namespace without a backend::namespace '$NAMESPACE' applies to no configured backend"
  fi
fi

# One server per host and port: a server left by an earlier job keeps that
# job's backend and makes --start-server fail with "Address in use", so stop
# it first. Starting now makes a broken install fail THIS step loudly, with
# the client's message; backend reachability still proves itself on first
# use, because sccache connects lazily.
"$bin" --stop-server >/dev/null 2>&1 || true
"$bin" --start-server >/dev/null 2>"$dir/start-server.log" || {
  echo "::error::sccache: the server did not start"
  sed 's/^/sccache: /' "$dir/start-server.log"
  exit 1
}

emit active true
emit bin "$bin"
if [ "$MODE" = "gha" ]; then
  echo "sccache: v$VERSION as RUSTC_WRAPPER (backend: the GitHub cache service)."
else
  echo "sccache: v$VERSION as RUSTC_WRAPPER (backend: SCCACHE_* from the job environment)."
fi
