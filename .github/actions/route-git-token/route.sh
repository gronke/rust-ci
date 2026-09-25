#!/usr/bin/env bash
# Export url.insteadOf rewrites as GIT_CONFIG_* environment entries via
# $GITHUB_ENV, appending after any entries an earlier invocation exported.
#   ROUTE_TOKEN     the token (required; masked before anything else)
#   ROUTE_HOST      git host, optionally with a port (default github.com)
#   ROUTE_USERNAME  userinfo name the token is presented under
#   ROUTE_PATH      optional namespace under the host to scope the rewrite to
#   ROUTE_REMAPS    optional lines of from=to, each sending fetches of an https
#                   URL to a repository path on the host (see git_remap_lines)
set -euo pipefail

# shellcheck source=../_lib/git-route.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/git-route.sh"

host="${ROUTE_HOST:-github.com}"
username="${ROUTE_USERNAME:-x-access-token}"

# Append behind existing entries: GIT_CONFIG_COUNT is the authoritative
# cursor, whether set by a previous invocation or by the workflow itself.
N="${GIT_CONFIG_COUNT:-0}"
lines="$(git_route_lines "${ROUTE_TOKEN:-}" "$host" "$username" "${ROUTE_PATH:-}" "$N")"
# The first line is the mask command for the log; the rest are the entries.
printf '%s\n' "$lines" | sed -n '1p'
entries="$(printf '%s\n' "$lines" | sed -n '2,$p')"
notes="Routing $(printf '%s\n' "$lines" | sed -n 's/^GIT_CONFIG_VALUE_[0-9]*=//p') fetches through the provided token (entry ${N})."

# Every remap is validated before anything reaches $GITHUB_ENV, so a refused
# line leaves the job's environment as it was.
n=$((N + 1))
while IFS= read -r line || [ -n "$line" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  case "$line" in
    *=*) ;;
    *)
      echo "::error::remap '${line}' is not a from=to line" >&2
      exit 1
      ;;
  esac
  remap="$(git_remap_lines "$ROUTE_TOKEN" "$host" "$username" "${line%%=*}" "${line#*=}" "$n")"
  entries+=$'\n'"$(printf '%s\n' "$remap" | sed -n '2,$p')"
  notes+=$'\n'"Remapping ${line%%=*} to https://${host}/${line#*=} (entry ${n})."
  n=$((n + 1))
done <<< "${ROUTE_REMAPS:-}"

printf '%s\n' "$entries" >> "$GITHUB_ENV"
printf '%s\n' "$notes"
