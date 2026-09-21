#!/usr/bin/env bash
# One namespace below the configured sccache backend's key prefix. Source it,
# then:
#
#   sccache_namespace_env release/linux-amd64 auto
#
# prints the NAME=VALUE line that puts this job's objects under
# <prefix>/release/linux-amd64 for whichever backend the job environment
# configures; the caller exports it and writes it to $GITHUB_ENV before the
# sccache server starts. Tiers or platforms then share one backend without
# sharing objects. A namespace separates objects, not writers: every job that
# reaches the backend can still write any key.
#
# The backend is the first configured one in sccache's own fallback order
# (S3, Redis, Memcached, GCS, the GitHub cache service, Azure, WebDAV, OSS,
# then the local disk cache), so the namespace lands where the objects go.
# The second argument is the action's mode: "gha" has no key prefix and is
# namespaced through SCCACHE_GHA_VERSION; a local SCCACHE_DIR gains a
# subdirectory. Without any backend nothing is printed.
#
# Grammar: segments of [A-Za-z0-9._-] joined by "/", nothing else. That is
# what the strictest backend, an S3 object proxy admitting key characters
# only, accepts; an empty segment and a query string fall out of it, and the
# dot-only segments "." and ".." are refused by name.

sccache_namespace_env() {
  local namespace="$1" mode="${2:-auto}"
  [ -n "$namespace" ] || return 0
  if ! printf '%s' "$namespace" | grep -Eq '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'; then
    echo "::error::sccache: namespace '$namespace' is not a path of [A-Za-z0-9._-] segments joined by /" >&2
    return 2
  fi
  # Dots alone are key characters too, so "." and ".." need refusing by name.
  case "/$namespace/" in
    */./* | */../*)
      echo "::error::sccache: namespace '$namespace' has a dot-only segment" >&2
      return 2
      ;;
  esac
  local prefix_var=""
  if [ -n "${SCCACHE_BUCKET:-}" ]; then
    prefix_var=SCCACHE_S3_KEY_PREFIX
  elif [ -n "${SCCACHE_REDIS_ENDPOINT:-}${SCCACHE_REDIS_CLUSTER_ENDPOINTS:-}${SCCACHE_REDIS:-}" ]; then
    prefix_var=SCCACHE_REDIS_KEY_PREFIX
  elif [ -n "${SCCACHE_MEMCACHED_ENDPOINT:-}${SCCACHE_MEMCACHED:-}" ]; then
    prefix_var=SCCACHE_MEMCACHED_KEY_PREFIX
  elif [ -n "${SCCACHE_GCS_BUCKET:-}" ]; then
    prefix_var=SCCACHE_GCS_KEY_PREFIX
  elif [ "$mode" = gha ] || [ "${SCCACHE_GHA_ENABLED:-}" = true ]; then
    prefix_var=SCCACHE_GHA_VERSION
  elif [ -n "${SCCACHE_AZURE_BLOB_CONTAINER:-}" ]; then
    prefix_var=SCCACHE_AZURE_KEY_PREFIX
  elif [ -n "${SCCACHE_WEBDAV_ENDPOINT:-}" ]; then
    prefix_var=SCCACHE_WEBDAV_KEY_PREFIX
  elif [ -n "${SCCACHE_OSS_BUCKET:-}" ]; then
    prefix_var=SCCACHE_OSS_KEY_PREFIX
  elif [ -n "${SCCACHE_DIR:-}" ]; then
    printf 'SCCACHE_DIR=%s/%s\n' "${SCCACHE_DIR%/}" "$namespace"
    return 0
  else
    return 0
  fi
  local current="${!prefix_var:-}"
  printf '%s=%s\n' "$prefix_var" "${current:+${current%/}/}$namespace"
}
