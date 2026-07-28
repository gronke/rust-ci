#!/usr/bin/env bash
# Build the reviewable candidate: render the changelog section into
# release-notes.md, create or refresh the draft pre-release, and push the next
# unsigned v<version>-rcN marker whose message carries the same notes. Inputs
# arrive as env vars from action.yml; git and gh run in the step's
# working-directory.
#   INPUT_VERSION        the version being drafted (no leading "v")
#   INPUT_PACKAGE        workspace member for the changelog render
#   INPUT_CHANGELOG      changelog path
#   INPUT_TITLE          notes/draft subject; empty means v<version>
#   INPUT_GIT_USER_NAME  committer identity for the marker tag
#   INPUT_GIT_USER_EMAIL committer email for the marker tag
set -euo pipefail

VERSION="$INPUT_VERSION"
TITLE="${INPUT_TITLE:-v${VERSION}}"

# --- the notes -----------------------------------------------------------------
# The released section, rendered plain. The draft body, the marker message and
# (through the runbook's -F command) the signed tag message are all this text.
INPUT_MODE="notes" INPUT_OUT="release-notes.md" INPUT_TITLE="$TITLE" \
  bash "$GITHUB_ACTION_PATH/../changelog/changelog.sh"

# --- the draft -----------------------------------------------------------------
notes=(--notes "Release v${VERSION}.")
[ -s release-notes.md ] && notes=(--notes-file release-notes.md)
if gh release view "v${VERSION}" >/dev/null 2>&1; then
  gh release edit "v${VERSION}" "${notes[@]}"
else
  gh release create "v${VERSION}" --draft --prerelease --title "$TITLE" "${notes[@]}"
fi
url="$(gh release view "v${VERSION}" --json url --jq .url)"

# --- the marker ----------------------------------------------------------------
git config user.name "$INPUT_GIT_USER_NAME"
git config user.email "$INPUT_GIT_USER_EMAIL"
n=1
while gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/v${VERSION}-rc${n}" >/dev/null 2>&1; do
  n=$((n + 1))
done
# The marker's message is release-notes.md (so promoting a candidate copies it
# into the signed tag), else a bare candidate label.
if [ -s release-notes.md ]; then
  git tag -a -F release-notes.md "v${VERSION}-rc${n}" "${GITHUB_SHA}"
else
  git tag -a -m "v${VERSION} candidate ${n}" "v${VERSION}-rc${n}" "${GITHUB_SHA}"
fi
git push origin "refs/tags/v${VERSION}-rc${n}" || {
  echo "::error::the marker push was rejected (GH013) — the tag ruleset must let Actions create unsigned v*-rc* markers: exclude v*-rc* from creation-restricting and signature-requiring tag rules."
  exit 1
}

{
  echo "marker=v${VERSION}-rc${n}"
  echo "url=${url}"
} >>"$GITHUB_OUTPUT"
