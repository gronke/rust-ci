#!/usr/bin/env bash
# Export an url.insteadOf rewrite as GIT_CONFIG_* environment entries via
# $GITHUB_ENV, appending after any entries an earlier invocation exported.
#   ROUTE_TOKEN     the token (required; masked before anything else)
#   ROUTE_HOST      git host, optionally with a port (default github.com)
#   ROUTE_USERNAME  userinfo name the token is presented under
#   ROUTE_PATH      optional namespace under the host to scope the rewrite to
set -euo pipefail

[ -n "${ROUTE_TOKEN:-}" ] || { echo "::error::token input is empty"; exit 1; }
printf '::add-mask::%s\n' "$ROUTE_TOKEN"

# Every validated piece ends up inside a gitconfig KEY; these gates keep
# injection structurally impossible.
HOST="${ROUTE_HOST:-github.com}"
if ! [[ "$HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]]; then
  echo "::error::host '${HOST}' is not a valid host[:port]"
  exit 1
fi

USERNAME="${ROUTE_USERNAME:-x-access-token}"
if ! [[ "$USERNAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "::error::username '${USERNAME}' is not a valid userinfo name"
  exit 1
fi

PREFIX="https://${HOST}/"
if [ -n "${ROUTE_PATH:-}" ]; then
  # One or more /-separated segments, each of the forge login/group charset
  # (GitLab namespaces nest, so a single segment would be too narrow).
  if ! [[ "$ROUTE_PATH" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(/[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?)*$ ]]; then
    echo "::error::path '${ROUTE_PATH}' is not a valid namespace path"
    exit 1
  fi
  PREFIX="https://${HOST}/${ROUTE_PATH}/"
fi

# Append behind existing entries: GIT_CONFIG_COUNT is the authoritative
# cursor, whether set by a previous invocation or by the workflow itself.
N="${GIT_CONFIG_COUNT:-0}"
{
  echo "GIT_CONFIG_COUNT=$((N + 1))"
  echo "GIT_CONFIG_KEY_${N}=url.https://${USERNAME}:${ROUTE_TOKEN}@${PREFIX#https://}.insteadOf"
  echo "GIT_CONFIG_VALUE_${N}=${PREFIX}"
  # cargo's libgit2 path ignores git config rewrites; the CLI honors them.
  echo "CARGO_NET_GIT_FETCH_WITH_CLI=true"
} >> "$GITHUB_ENV"

echo "Routing ${PREFIX} fetches through the provided token (entry ${N})."
