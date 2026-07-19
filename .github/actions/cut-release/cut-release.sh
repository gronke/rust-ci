#!/usr/bin/env bash
# Start a release: cut the changelog for the crate's declared version, push
# the release branch, open the merge-back pull request, and dispatch the
# release pipeline. Inputs arrive as env vars from action.yml; cargo, git,
# and gh run in the step's working directory.
#   INPUT_BRANCH_PREFIX     release branch name prefix (the version follows)
#   INPUT_BASE              merge-back base branch (else the repo default)
#   INPUT_PIPELINE_WORKFLOW workflow file to dispatch (empty skips)
#   INPUT_MERGE_BACK        "true" opens the merge-back pull request
#   INPUT_PACKAGE           package name (required for a multi-member workspace)
#   INPUT_CHANGELOG         changelog path, relative to the working directory
#   INPUT_DATE              date stamped on the released section (else today, UTC)
#   INPUT_DRY_RUN           "true" cuts the working tree but touches no remote
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/crate-version.sh"

resolve_crate "${INPUT_PACKAGE:-}"
VERSION="$CRATE_VERSION"
BRANCH="${INPUT_BRANCH_PREFIX:-release/v}${VERSION}"

# The branch guard runs first, before the changelog rewrite touches the tree.
# A missing origin counts as "does not exist" (scratch checkouts, dry runs).
if git ls-remote --exit-code origin "refs/heads/${BRANCH}" >/dev/null 2>&1; then
  echo "::error::${BRANCH} already exists"
  exit 1
fi

# The sibling changelog action performs the cut: [Unreleased] becomes the
# released section for $VERSION, the compare link is rewritten, and
# CHANGELOG_VERSION lands in the job environment.
INPUT_MODE="cut" bash "$GITHUB_ACTION_PATH/../changelog/changelog.sh"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${VERSION}"
    echo "branch=${BRANCH}"
  } >>"$GITHUB_OUTPUT"
fi

if [ "${INPUT_DRY_RUN:-false}" = "true" ]; then
  echo "✓ dry run: would cut ${BRANCH} for ${VERSION} (changelog rewritten in the working tree only)"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git switch -c "${BRANCH}"
git add "${INPUT_CHANGELOG:-CHANGELOG.md}"
git commit -m "chore: release v${VERSION}"
git push origin "${BRANCH}"

if [ "${INPUT_MERGE_BACK:-true}" = "true" ]; then
  BASE="${INPUT_BASE:-}"
  if [ -z "$BASE" ]; then
    BASE="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '.default_branch')"
  fi
  gh pr create --repo "${GITHUB_REPOSITORY}" --base "$BASE" --head "${BRANCH}" \
    --title "chore: release v${VERSION}" \
    --body "Merge-back of the release branch: the changelog section for v${VERSION}. The release pipeline builds every push of this branch into the v${VERSION} draft pre-release."
fi

if [ -n "${INPUT_PIPELINE_WORKFLOW:-}" ]; then
  gh workflow run "${INPUT_PIPELINE_WORKFLOW}" --repo "${GITHUB_REPOSITORY}" --ref "${BRANCH}"
fi

echo "✓ cut ${BRANCH} for ${VERSION}"
