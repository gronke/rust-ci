#!/usr/bin/env bash
# Shared git routing: an url.insteadOf rewrite that presents a token for one
# https host (optionally one namespace under it), expressed as GIT_CONFIG_*
# environment entries so it dies with the job and never lands in a gitconfig
# file. Source it, then call:
#
#   git_route_lines <token> <host> <username> <path> <start-index>
#
# It validates every piece (the token first, before it is masked or embedded),
# prints `::add-mask::<token>` to stdout for the runner to redact, and prints
# the environment lines the caller appends to $GITHUB_ENV or to a sealed
# container's env-file:
#   GIT_CONFIG_COUNT=<start-index + 1>
#   GIT_CONFIG_KEY_<start-index>=url.https://<username>:<token>@<host>/<path>/.insteadOf
#   GIT_CONFIG_VALUE_<start-index>=https://<host>/<path>/
#   CARGO_NET_GIT_FETCH_WITH_CLI=true
# cargo's libgit2 path ignores git config rewrites; the git CLI honors them.
# A validation failure prints ::error:: and returns 1 without echoing the token.
git_route_lines() {
  local token="$1" host="${2:-github.com}" username="${3:-x-access-token}" path="${4:-}" n="${5:-0}"
  [ -n "$token" ] || { echo "::error::token input is empty" >&2; return 1; }
  # The token ends up inside one environment line: a newline would write a line
  # of its own, and `::add-mask::` would only have masked the first line. The
  # charset covers what forges issue (GitHub ghs_/github_pat_, GitLab glpat-,
  # Bitbucket, base64url JWTs) and excludes what would break the URL.
  if ! [[ "$token" =~ ^[A-Za-z0-9._~+=-]+$ ]]; then
    echo "::error::the token contains characters this action cannot embed in a git URL (whitespace, or one of @:/?#%); percent-encode it, or mint one without them" >&2
    return 1
  fi
  if ! [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]]; then
    echo "::error::host '${host}' is not a valid host[:port]" >&2
    return 1
  fi
  if ! [[ "$username" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "::error::username '${username}' is not a valid userinfo name" >&2
    return 1
  fi
  local prefix="https://${host}/"
  if [ -n "$path" ]; then
    # One or more /-separated segments of the forge login/group charset.
    if ! [[ "$path" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(/[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?)*$ ]]; then
      echo "::error::path '${path}' is not a valid namespace path" >&2
      return 1
    fi
    prefix="https://${host}/${path}/"
  fi
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "::error::GIT_CONFIG_COUNT '${n}' is not a number" >&2
    return 1
  fi
  printf '::add-mask::%s\n' "$token"
  printf 'GIT_CONFIG_COUNT=%s\n' "$((n + 1))"
  printf 'GIT_CONFIG_KEY_%s=url.https://%s:%s@%s.insteadOf\n' "$n" "$username" "$token" "${prefix#https://}"
  printf 'GIT_CONFIG_VALUE_%s=%s\n' "$n" "$prefix"
  printf 'CARGO_NET_GIT_FETCH_WITH_CLI=true\n'
}
