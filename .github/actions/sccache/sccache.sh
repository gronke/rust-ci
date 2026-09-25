#!/usr/bin/env bash
# Inputs arrive as env vars from action.yml:
#   MODE            auto | on | off
#   ARCHIVED        "true" when archive.sh set up the archived SCCACHE_DIR
#   NAMESPACE       path below the backend's key prefix ("" for none)
#   WRITE           "true" | "false"; false reads the backend without storing
#   VERSION         sccache release (X.Y.Z, no v prefix)
#   STARTUP_TIMEOUT_MS  server_startup_timeout_ms for sccache's configuration file
#   SHA256_X86_64   pinned archive checksum, x86_64-unknown-linux-musl
#   SHA256_AARCH64  pinned archive checksum, aarch64-unknown-linux-musl
set -euo pipefail

# shellcheck source=../_lib/install-release.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/install-release.sh"
# shellcheck source=../_lib/sccache-backend.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/sccache-backend.sh"

MODE="${MODE:-auto}"
WRITE="${WRITE:-true}"
emit() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }

case "$WRITE" in
  true | false) ;;
  *)
    echo "::error::sccache: write must be \"true\" or \"false\" (got '$WRITE')"
    exit 1
    ;;
esac

# The backend sccache itself will use (_lib/sccache-backend.sh); sccache
# reads the variables itself. A present-but-empty variable (an unset `vars.*`
# expression) configures nothing, and neither do tuning variables such as
# SCCACHE_CACHE_SIZE on their own.
backend=$(sccache_backend)
read -r kind _ _ endpoint_var <<<"$backend"

active=false
case "$MODE" in
  off) ;;
  on) active=true ;;
  auto) [ -n "$backend" ] && active=true ;;
  *)
    echo "::error::sccache: invalid mode '$MODE' (auto|on|off)"
    exit 1
    ;;
esac

# sccache's own GitHub cache backend needs a runtime token this action no
# longer exports; a job environment still asking for it fails here rather
# than at the first compile. Checked before the inactive exit, so the
# leftover fails an auto mode that would otherwise no-op silently; only
# mode "off" stays a true no-op.
if [ "$MODE" != off ]; then
  gha_enabled="${SCCACHE_GHA_ENABLED:-}"
  case "${gha_enabled,,}" in
    '' | 0 | false | off) gha_enabled="" ;;
  esac
  if [ -n "$gha_enabled" ] || [ -n "${SCCACHE_GHA_VERSION:-}" ]; then
    echo "::error::sccache: SCCACHE_GHA_ENABLED or SCCACHE_GHA_VERSION is set, but this action no longer wires the GitHub cache service backend; drop the variable and name an archive"
    exit 1
  fi
fi

if [ "$active" != true ]; then
  emit active false
  emit bin ""
  exit 0
fi

[ -n "$backend" ] || echo "::warning title=sccache without a backend::No sccache backend is configured and no archive engaged; sccache falls back to its local-disk default, which an ephemeral runner throws away."

triple=$(release_target) || exit 1
sha=$(release_sha "$SHA256_X86_64" "$SHA256_AARCH64")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "::error::sccache: invalid version '$VERSION'"
  exit 1
}
[[ "$STARTUP_TIMEOUT_MS" =~ ^[0-9]{1,7}$ ]] || {
  echo "::error::sccache: server-startup-timeout-ms must be a number of milliseconds (got '$STARTUP_TIMEOUT_MS')"
  exit 1
}

# A namespace puts this job's objects below the backend's key prefix, and
# write: false reads the backend and stores nothing, through the backend's own
# read/write mode; both are settled here, before anything reaches
# $GITHUB_ENV, so a refusal leaves the job's environment as it was. The read/
# write mode is a client setting: a backend that takes writes from any job
# still does. write: true exports only the GCS READ_WRITE that sccache's own
# read-only default there makes necessary. An archived directory stays
# writable, since only a writer saves the archive: a reader's objects serve
# its own later compiles and leave with the runner.
namespaced=""
if [ -n "${NAMESPACE:-}" ]; then
  namespaced=$(sccache_namespace_env "$NAMESPACE") || exit 1
  [ -n "$namespaced" ] || echo "::warning title=sccache namespace without a backend::namespace '$NAMESPACE' applies to no configured backend"
fi
rw=""
if [ "${ARCHIVED:-false}" != true ]; then
  rw=$(sccache_rw_env "$WRITE") || exit 1
fi

# Static musl build under RUNNER_TEMP: inside a job container that is the
# bind-mounted _work/_temp, so the absolute RUSTC_WRAPPER path below stays
# valid for every later step without touching PATH.
dir="${RUNNER_TEMP:-/tmp}/rust-ci-sccache"
bin="$dir/sccache"
if [ ! -x "$bin" ]; then
  install_release "https://github.com/mozilla/sccache/releases/download/v${VERSION}/sccache-v${VERSION}-${triple}.tar.gz" \
    "$sha" sccache "$dir" || exit 1
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
if [ -z "${SCCACHE_CONF:-}" ] && [ ! -f "$(sccache_config_file)" ]; then
  conf="$dir/config.toml"
  printf 'server_startup_timeout_ms = %s\n' "$STARTUP_TIMEOUT_MS" > "$conf"
  echo "SCCACHE_CONF=$conf" >> "$GITHUB_ENV"
  export SCCACHE_CONF="$conf"
fi

# Exported for the server started below, and written to $GITHUB_ENV for
# every compile after this step.
for line in "$namespaced" "$rw"; do
  [ -n "$line" ] || continue
  printf '%s\n' "$line" >> "$GITHUB_ENV"
  # shellcheck disable=SC2163  # the NAME=VALUE line is the export
  export "$line"
done
[ -z "$namespaced" ] || echo "sccache: namespace $NAMESPACE (${namespaced%%=*})"
[ -z "$rw" ] || echo "sccache: ${rw#*=} (${rw%%=*})"

# A backend that does not answer turns every compile into a miss; say so here
# rather than leaving it to a slow build to show.
if [ -n "${endpoint_var:-}" ] && [ "$endpoint_var" != - ] && [ -n "${!endpoint_var:-}" ]; then
  sccache_endpoint_answers "${!endpoint_var}" \
    || echo "::warning title=sccache backend unreachable::${endpoint_var} ${!endpoint_var} does not answer; compiles run with cache misses"
fi

# One server per host and port: a server left by an earlier job keeps that
# job's backend and makes --start-server fail with "Address in use", so stop
# it first. Starting now makes a broken install fail THIS step loudly, with
# the client's message.
"$bin" --stop-server >/dev/null 2>&1 || true
"$bin" --start-server >/dev/null 2>"$dir/start-server.log" || {
  echo "::error::sccache: the server did not start"
  sed 's/^/sccache: /' "$dir/start-server.log"
  exit 1
}

# The started server reports where its objects go. Where the action placed
# them (a namespace, a read/write mode, an archive), that has to be the
# backend it detected: one that sccache configures from a source the
# detection does not read would take the objects past the namespace or the
# read-only mode, so the step fails instead.
if [ -n "$namespaced$rw" ] || [ "${ARCHIVED:-false}" = true ]; then
  want="${kind:-disk}"
  location=$("$bin" --show-stats --stats-format=json 2>/dev/null \
    | sed -n 's/.*"cache_location":"\([^"\\]*\).*/\1/p') || true
  got=$(sccache_location_kind "$location")
  if [ "$got" != "$want" ]; then
    "$bin" --stop-server >/dev/null 2>&1 || true
    echo "::error::sccache: the server stores to '${location:-an unknown location}', not to the $want backend the action configured"
    exit 1
  fi
fi

emit active true
emit bin "$bin"
if [ "${ARCHIVED:-false}" = true ]; then
  echo "sccache: v$VERSION as RUSTC_WRAPPER (backend: $SCCACHE_DIR, carried as a GitHub Actions cache archive)."
else
  echo "sccache: v$VERSION as RUSTC_WRAPPER (backend: ${kind:-local disk})."
fi
