#!/usr/bin/env bash
# Export an url.insteadOf rewrite as GIT_CONFIG_* environment entries via
# $GITHUB_ENV, appending after any entries an earlier invocation exported.
#   ROUTE_TOKEN     the token (required; masked before anything else)
#   ROUTE_HOST      git host, optionally with a port (default github.com)
#   ROUTE_USERNAME  userinfo name the token is presented under
#   ROUTE_PATH      optional namespace under the host to scope the rewrite to
set -euo pipefail

# shellcheck source=../_lib/git-route.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/git-route.sh"

# Append behind existing entries: GIT_CONFIG_COUNT is the authoritative
# cursor, whether set by a previous invocation or by the workflow itself.
N="${GIT_CONFIG_COUNT:-0}"
lines="$(git_route_lines "${ROUTE_TOKEN:-}" "${ROUTE_HOST:-github.com}" "${ROUTE_USERNAME:-x-access-token}" "${ROUTE_PATH:-}" "$N")"
# The first line is the mask command for the log; the rest are the entries.
printf '%s\n' "$lines" | sed -n '1p'
printf '%s\n' "$lines" | sed -n '2,$p' >> "$GITHUB_ENV"
prefix="$(printf '%s\n' "$lines" | sed -n 's/^GIT_CONFIG_VALUE_[0-9]*=//p')"
echo "Routing ${prefix} fetches through the provided token (entry ${N})."
