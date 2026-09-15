#!/usr/bin/env bash
# Shared resolver for the version a changelog declares — the manifest
# equivalent of a repository without a Cargo.toml. Source it, then call:
#
#   resolve_changelog_version <changelog-path>   # sets CHANGELOG_LATEST
#
# CHANGELOG_LATEST is the version of the newest released section heading
# (`## [X.Y.Z] ...`, first in the file; Keep a Changelog orders newest first);
# empty when no released section exists.
# shellcheck disable=SC2034  # CHANGELOG_LATEST is read by the sourcing action
resolve_changelog_version() {
  local changelog="${1:-CHANGELOG.md}"
  CHANGELOG_LATEST=""
  if [ ! -f "$changelog" ]; then
    echo "::error::no changelog at $changelog"
    return 1
  fi
  CHANGELOG_LATEST="$(grep -m1 -oE '^## \[[0-9][^]]*\]' "$changelog" | sed -E 's/^## \[([^]]+)\]$/\1/')"
}
