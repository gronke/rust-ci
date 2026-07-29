#!/usr/bin/env bash
# Publish the reviewed candidate: seal the final tag against the newest
# v<version>-rcN marker by tree, flip the draft live, optionally advance the
# moving major. Inputs arrive as env vars from action.yml; git and gh run in
# the step's working-directory.
#   INPUT_VERSION        the version being published (no leading "v")
#   INPUT_SEAL_ONLY      "true" verifies the seal and stops (a cheap early gate)
#   INPUT_TAG_SHA        commit the tag points at (default: this run's GITHUB_SHA)
#   INPUT_MOVING_MAJOR   "true" advances the moving v<MAJOR> tag
#   INPUT_GIT_USER_NAME  committer identity for the moving major tag
#   INPUT_GIT_USER_EMAIL committer email for the moving major tag
set -euo pipefail

VERSION="$INPUT_VERSION"
TAG_SHA="${INPUT_TAG_SHA:-$GITHUB_SHA}"

# --- the seal ------------------------------------------------------------------
n=1
while gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/v${VERSION}-rc$((n + 1))" >/dev/null 2>&1; do
  n=$((n + 1))
done
MARKER="v${VERSION}-rc${n}"
gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${MARKER}" >/dev/null 2>&1 || {
  echo "::error::no candidate marker for v${VERSION} — the pipeline publishes only reviewed candidates (cut a release branch first)"
  exit 1
}
marker_commit="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${MARKER}" --jq '.object.sha')"
marker_commit="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${marker_commit}" --jq '.object.sha' 2>/dev/null || printf '%s' "$marker_commit")"
# The seal is the content, not the commit: a rebase-merged merge-back rewrites
# the SHA but carries the identical tree, and that tip is a valid tag target.
# Trees resolve through the API — no history needed.
tag_tree="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${TAG_SHA}" --jq '.commit.tree.sha')"
marker_tree="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${marker_commit}" --jq '.commit.tree.sha')"
if [ "$tag_tree" != "$marker_tree" ]; then
  echo "::error::v${VERSION} (${TAG_SHA}, tree ${tag_tree}) does not carry the content the last build sealed (${MARKER} at ${marker_commit}, tree ${marker_tree})"
  exit 1
fi

# Seal-only: the early gate. Running this before the artifact jobs turns a
# mis-pointed tag into a seconds-long failure instead of one that surfaces after
# every binary has been built. The full call re-seals (four API calls), so the
# action stays self-contained for pipelines without the early gate.
if [ "${INPUT_SEAL_ONLY:-false}" = "true" ]; then
  echo "seal-only: not flipping the draft, not touching the moving major"
  echo "marker=${MARKER}" >>"$GITHUB_OUTPUT"
  exit 0
fi

# --- the flip ------------------------------------------------------------------
# A stable version sheds the --prerelease the draft was created with.
case "$VERSION" in
  *-*) gh release edit "v${VERSION}" --draft=false ;;
  *) gh release edit "v${VERSION}" --draft=false --prerelease=false ;;
esac

# --- the moving major ----------------------------------------------------------
if [ "$INPUT_MOVING_MAJOR" = "true" ]; then
  case "$VERSION" in
  *-*)
    echo "prerelease; the moving major stays"
    ;;
  *)
    MAJOR="v${VERSION%%.*}"
    git config user.name "$INPUT_GIT_USER_NAME"
    git config user.email "$INPUT_GIT_USER_EMAIL"
    # The highest STABLE tag in this line — publishing an older patch (e.g. a
    # backport) must not rewind the major.
    git fetch --tags --force --quiet origin
    highest="$(git tag --list "${MAJOR}.*" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)" || true
    test -n "$highest" || {
      echo "::error::no stable ${MAJOR}.x tag found"
      exit 1
    }
    target="$(git rev-list -n1 "$highest")"
    # Defense-in-depth: only ever point the major tag at a commit on the
    # default branch.
    default_branch="$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch)"
    git fetch --no-tags --quiet origin "$default_branch"
    git merge-base --is-ancestor "$target" FETCH_HEAD || {
      echo "::error::${highest} (${target}) is not on ${default_branch}; refusing to move ${MAJOR}"
      exit 1
    }
    git push origin ":refs/tags/${MAJOR}" || true # delete the old tag (ignore if absent)
    git tag -f -a -m "${MAJOR} (moving major) -> ${highest}" "${MAJOR}" "${target}"
    git push -f origin "refs/tags/${MAJOR}"
    echo "moving major: ${MAJOR} -> ${highest} (${target})"
    ;;
  esac
fi

echo "marker=${MARKER}" >>"$GITHUB_OUTPUT"
