#!/usr/bin/env bash
# The sccache backend the job environment configures, and what the sccache
# action derives from it. Source it, then:
#
#   sccache_backend                      kind, prefix variable, read/write variable, endpoint variable
#   sccache_config_file                  the configuration file sccache reads
#   sccache_namespace_valid <namespace>  whether a namespace fits the grammar below
#   sccache_namespace_env <namespace>    NAME=VALUE that puts the objects below the backend's prefix
#   sccache_rw_env <write>               NAME=READ_ONLY when write is "false"
#   sccache_location_kind <location>     the backend kind of the cache location a server reports
#   sccache_endpoint_answers <url>       whether an http(s) endpoint answers at all
#
# The rules are those of sccache 0.17.0, the pinned release. A multi-level
# chain (SCCACHE_MULTILEVEL_CHAIN) comes first, then a cache in sccache's
# configuration file, which sccache merges with the environment backend by
# backend; both print as kinds without variables ("multilevel - - -",
# "file - - -"), so the action activates on them and leaves them as they
# are configured. Otherwise the backend is the first configured one in
# sccache's own fallback order (S3, Redis, Memcached, GCS, Azure, WebDAV,
# OSS, COS, then a local SCCACHE_DIR), so what the action exports lands where
# the objects go. Without any backend, the functions print nothing.

sccache_backend() {
  if [ -n "${SCCACHE_MULTILEVEL_CHAIN:-}" ]; then
    echo "multilevel - - -"
  elif _sccache_file_caches "$(sccache_config_file)"; then
    echo "file - - -"
  elif [ -n "${SCCACHE_BUCKET:-}" ]; then
    echo "s3 SCCACHE_S3_KEY_PREFIX SCCACHE_S3_RW_MODE SCCACHE_ENDPOINT"
  elif [ -n "${SCCACHE_REDIS_ENDPOINT:-}${SCCACHE_REDIS_CLUSTER_ENDPOINTS:-}${SCCACHE_REDIS:-}" ]; then
    echo "redis SCCACHE_REDIS_KEY_PREFIX SCCACHE_REDIS_RW_MODE -"
  elif [ -n "${SCCACHE_MEMCACHED_ENDPOINT:-}${SCCACHE_MEMCACHED:-}" ]; then
    echo "memcached SCCACHE_MEMCACHED_KEY_PREFIX SCCACHE_MEMCACHED_RW_MODE -"
  elif [ -n "${SCCACHE_GCS_BUCKET:-}" ]; then
    echo "gcs SCCACHE_GCS_KEY_PREFIX SCCACHE_GCS_RW_MODE -"
  # Azure needs the container and the connection string together; 0.17.0
  # knows no other way to authenticate.
  elif [ -n "${SCCACHE_AZURE_BLOB_CONTAINER:-}" ] && [ -n "${SCCACHE_AZURE_CONNECTION_STRING:-}" ]; then
    echo "azure SCCACHE_AZURE_KEY_PREFIX SCCACHE_AZURE_RW_MODE -"
  elif [ -n "${SCCACHE_WEBDAV_ENDPOINT:-}" ]; then
    echo "webdav SCCACHE_WEBDAV_KEY_PREFIX SCCACHE_WEBDAV_RW_MODE SCCACHE_WEBDAV_ENDPOINT"
  elif [ -n "${SCCACHE_OSS_BUCKET:-}" ]; then
    echo "oss SCCACHE_OSS_KEY_PREFIX SCCACHE_OSS_RW_MODE SCCACHE_OSS_ENDPOINT"
  elif [ -n "${SCCACHE_COS_BUCKET:-}" ]; then
    echo "cos SCCACHE_COS_KEY_PREFIX SCCACHE_COS_RW_MODE SCCACHE_COS_ENDPOINT"
  elif [ -n "${SCCACHE_DIR:-}" ]; then
    echo "disk SCCACHE_DIR SCCACHE_LOCAL_RW_MODE -"
  fi
}

# SCCACHE_CONF when set, empty included (sccache then reads no file),
# otherwise the default path: $XDG_CONFIG_HOME/sccache/config when that is
# absolute, ~/.config/sccache/config otherwise.
sccache_config_file() {
  if [ -n "${SCCACHE_CONF+x}" ]; then
    printf '%s\n' "$SCCACHE_CONF"
    return 0
  fi
  local base="${XDG_CONFIG_HOME:-}"
  case "$base" in
    /*) ;;
    *) base="${HOME:-}/.config" ;;
  esac
  printf '%s\n' "$base/sccache/config"
}

# A configuration file configures a cache when it holds a [cache] or
# [cache.<kind>] table, a dotted cache.<kind> key or an inline cache table,
# or, as a .json file, a "cache" key. A disk table counts too: the
# environment's disk settings replace it as a whole, its directory included.
_sccache_file_caches() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 1
  case "$file" in
    *.json) grep -Eq '"cache"[[:space:]]*:' "$file" ;;
    *) grep -Eq "^[[:space:]]*(\[[[:space:]]*[\"']?cache[\"']?[[:space:]]*[].]|[\"']?cache[\"']?[[:space:]]*[.=])" "$file" ;;
  esac
}

# Grammar: segments of [A-Za-z0-9._-] joined by "/", nothing else. That is
# what the strictest backend, an S3 object proxy admitting key characters
# only, accepts; an empty segment and a query string fall out of it, and the
# dot-only segments "." and ".." are refused by name.
sccache_namespace_valid() {
  local namespace="$1"
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
}

# Puts the job's objects under <prefix>/<namespace>; the caller exports the
# line and writes it to $GITHUB_ENV before the sccache server starts, so tiers
# or platforms share one backend without sharing objects. A namespace
# separates objects, not writers: every job that reaches the backend can still
# write any key. A local SCCACHE_DIR gains a subdirectory. A backend without
# variables (a multi-level chain, a configuration file) takes no namespace.
sccache_namespace_env() {
  local namespace="$1" kind prefix_var
  [ -n "$namespace" ] || return 0
  sccache_namespace_valid "$namespace" || return 2
  read -r kind prefix_var _ <<<"$(sccache_backend)"
  [ -n "${kind:-}" ] || return 0
  if [ "$prefix_var" = - ]; then
    echo "::error::sccache: namespace '$namespace' needs a backend configured through SCCACHE_* variables; this one comes from $(_sccache_kind_source "$kind")" >&2
    return 2
  fi
  local current="${!prefix_var:-}"
  printf '%s=%s\n' "$prefix_var" "${current:+${current%/}/}$namespace"
}

# sccache writes by default, except GCS, which sccache itself defaults to
# READ_ONLY. With write "false" the backend's own read/write mode becomes
# READ_ONLY, so the job reads what others stored and stores nothing; with
# "true" nothing is exported but the GCS READ_WRITE that spells the default
# out, and a mode the host set stays in force either way. A backend without
# variables cannot be switched to read-only, so write "false" refuses it.
sccache_rw_env() {
  local write="$1" kind rw_var
  case "$write" in
    true | false) ;;
    *)
      echo "::error::sccache: write must be \"true\" or \"false\" (got '$write')" >&2
      return 2
      ;;
  esac
  read -r kind _ rw_var _ <<<"$(sccache_backend)"
  [ -n "${kind:-}" ] || return 0
  if [ "$rw_var" = - ]; then
    if [ "$write" = false ]; then
      echo "::error::sccache: write \"false\" needs a backend configured through SCCACHE_* variables; this one comes from $(_sccache_kind_source "$kind")" >&2
      return 2
    fi
    return 0
  fi
  if [ "$write" = false ]; then
    printf '%s=READ_ONLY\n' "$rw_var"
  elif [ "$kind" = gcs ] && [ -z "${SCCACHE_GCS_RW_MODE:-}" ]; then
    printf '%s=READ_WRITE\n' "$rw_var"
  fi
}

_sccache_kind_source() {
  case "$1" in
    multilevel) echo "a multi-level chain (SCCACHE_MULTILEVEL_CHAIN)" ;;
    file) echo "sccache's configuration file $(sccache_config_file)" ;;
  esac
}

# The kind sccache_backend names for the cache location a started server
# reports (`sccache --show-stats`): "Local disk: …" is disk, "Multi-level …"
# a chain, and a remote store reports its scheme first ("s3, name: …"),
# where Azure's is azblob.
sccache_location_kind() {
  local location="$1" scheme
  case "$location" in
    "Local disk"*) echo disk ;;
    Multi-level*) echo multilevel ;;
    *,*)
      scheme="${location%%,*}"
      case "$scheme" in
        azblob) echo azure ;;
        *) echo "$scheme" ;;
      esac
      ;;
  esac
}

# Any HTTP status counts as an answer; only a refused, reset or timed-out
# connection does not. Reachability is all the action can check without
# knowing the host's health path.
sccache_endpoint_answers() {
  local url="$1" code
  case "$url" in
    http://* | https://*) ;;
    *) return 0 ;;
  esac
  code=$(curl -sS -m 3 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null) || true
  [ -n "$code" ] && [ "$code" != 000 ]
}
