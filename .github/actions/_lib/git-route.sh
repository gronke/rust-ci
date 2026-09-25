#!/usr/bin/env bash
# Shared git routing: url.insteadOf rewrites that present a token for one
# https host, expressed as GIT_CONFIG_* environment entries so they die with
# the job and never land in a gitconfig file. Source it, then call:
#
#   git_route_lines <token> <host> <username> <path> <start-index>
#   git_remap_lines <token> <host> <username> <from> <to> <start-index>
#
# git_route_lines routes the host, optionally one namespace under it:
#   GIT_CONFIG_COUNT=<start-index + 1>
#   GIT_CONFIG_KEY_<start-index>=url.https://<username>:<token>@<host>/<path>/.insteadOf
#   GIT_CONFIG_VALUE_<start-index>=https://<host>/<path>/
#   CARGO_NET_GIT_FETCH_WITH_CLI=true
# git_remap_lines sends fetches of <from>, an https URL on any host, to <to>,
# a repository path on the routed host, with the token presented:
#   GIT_CONFIG_COUNT=<start-index + 1>
#   GIT_CONFIG_KEY_<start-index>=url.https://<username>:<token>@<host>/<to>.insteadOf
#   GIT_CONFIG_VALUE_<start-index>=<from>
# git applies the longest matching insteadOf value, so a remap outranks a
# namespace rewrite that matches the same URL.
#
# Both validate every piece (the token first, before it is masked or
# embedded), print `::add-mask::<token>` to stdout for the runner to redact,
# then the environment lines the caller appends to $GITHUB_ENV or to a sealed
# container's env-file. cargo's libgit2 path ignores git config rewrites; the
# git CLI honors them. A validation failure prints ::error:: and returns 1
# without echoing the token.

# One or more /-separated segments of the forge login/group/repository charset.
_GIT_ROUTE_PATH_RE='^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(/[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?)*$'
_GIT_ROUTE_HOST_RE='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'

# The pieces every entry embeds: token, host, userinfo name, start index.
_git_route_check() {
  local token="$1" host="$2" username="$3" n="$4"
  [ -n "$token" ] || { echo "::error::token input is empty" >&2; return 1; }
  # The token ends up inside one environment line: a newline would write a line
  # of its own, and `::add-mask::` would only have masked the first line. The
  # charset covers what forges issue (GitHub ghs_/github_pat_, GitLab glpat-,
  # Bitbucket, base64url JWTs) and excludes what would break the URL.
  if ! [[ "$token" =~ ^[A-Za-z0-9._~+=-]+$ ]]; then
    echo "::error::the token contains characters this action cannot embed in a git URL (whitespace, or one of @:/?#%); percent-encode it, or mint one without them" >&2
    return 1
  fi
  if ! [[ "$host" =~ $_GIT_ROUTE_HOST_RE ]]; then
    echo "::error::host '${host}' is not a valid host[:port]" >&2
    return 1
  fi
  if ! [[ "$username" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "::error::username '${username}' is not a valid userinfo name" >&2
    return 1
  fi
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "::error::GIT_CONFIG_COUNT '${n}' is not a number" >&2
    return 1
  fi
}

git_route_lines() {
  local token="$1" host="${2:-github.com}" username="${3:-x-access-token}" path="${4:-}" n="${5:-0}"
  _git_route_check "$token" "$host" "$username" "$n" || return 1
  local prefix="https://${host}/"
  if [ -n "$path" ]; then
    if ! [[ "$path" =~ $_GIT_ROUTE_PATH_RE ]]; then
      echo "::error::path '${path}' is not a valid namespace path" >&2
      return 1
    fi
    prefix="https://${host}/${path}/"
  fi
  printf '::add-mask::%s\n' "$token"
  printf 'GIT_CONFIG_COUNT=%s\n' "$((n + 1))"
  printf 'GIT_CONFIG_KEY_%s=url.https://%s:%s@%s.insteadOf\n' "$n" "$username" "$token" "${prefix#https://}"
  printf 'GIT_CONFIG_VALUE_%s=%s\n' "$n" "$prefix"
  printf 'CARGO_NET_GIT_FETCH_WITH_CLI=true\n'
}

git_remap_lines() {
  local token="$1" host="${2:-github.com}" username="${3:-x-access-token}" from="${4:-}" to="${5:-}" n="${6:-0}"
  _git_route_check "$token" "$host" "$username" "$n" || return 1
  # An https URL prefix without credentials, query or fragment.
  local from_re='^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?(/[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?)+$'
  if ! [[ "$from" =~ $from_re ]]; then
    echo "::error::remap source '${from}' is not an https URL of host and path segments" >&2
    return 1
  fi
  if ! [[ "$to" =~ $_GIT_ROUTE_PATH_RE ]]; then
    echo "::error::remap target '${to}' is not a repository path on ${host}" >&2
    return 1
  fi
  printf '::add-mask::%s\n' "$token"
  printf 'GIT_CONFIG_COUNT=%s\n' "$((n + 1))"
  printf 'GIT_CONFIG_KEY_%s=url.https://%s:%s@%s/%s.insteadOf\n' "$n" "$username" "$token" "$host" "$to"
  printf 'GIT_CONFIG_VALUE_%s=%s\n' "$n" "$from"
}
