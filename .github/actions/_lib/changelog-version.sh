#!/usr/bin/env bash
# Shared resolver for the version a changelog declares — the manifest
# equivalent of a repository without a Cargo.toml. Source it, then call:
#
#   resolve_changelog_version <changelog-path>   # sets CHANGELOG_LATEST, CHANGELOG_UNRELEASED_EMPTY
#
# CHANGELOG_LATEST is the version of the newest released section heading
# (`## [X.Y.Z] …`, first in the file — Keep a Changelog orders newest first);
# empty when no released section exists. CHANGELOG_UNRELEASED_EMPTY is "true"
# when the [Unreleased] section is absent or carries no content. Together they
# answer the release question: an empty [Unreleased] with the newest section's
# tag missing names the release in flight; with the tag present, nothing is
# left to release.
resolve_changelog_version() {
  local changelog="${1:-CHANGELOG.md}" body
  CHANGELOG_LATEST=""
  CHANGELOG_UNRELEASED_EMPTY="true"
  if [ ! -f "$changelog" ]; then
    echo "::error::no changelog at $changelog"
    return 1
  fi
  CHANGELOG_LATEST="$(grep -m1 -oE '^## \[[0-9][^]]*\]' "$changelog" | sed -E 's/^## \[([^]]+)\]$/\1/')"
  body="$(awk '/^## \[Unreleased\]/{grab=1; next} /^## /{grab=0} /^\[[^]]+\]: /{grab=0} grab' "$changelog")"
  if [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    CHANGELOG_UNRELEASED_EMPTY="false"
  fi
}
