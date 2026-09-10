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
#   INPUT_VERSION           the version to release (else resolved from Cargo.toml)
#   INPUT_CHANGELOG         changelog path, relative to the working directory
#   INPUT_DATE              date stamped on the released section (else today, UTC)
#   INPUT_CITATION          Citation File Format path (empty disables; absent file skips)
#   INPUT_DRY_RUN           "true" cuts the working tree but touches no remote
#   INPUT_GIT_USER_NAME     committer identity for the release commit
#   INPUT_GIT_USER_EMAIL    committer email (default: the github-actions bot)
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/crate-version.sh"

# The version: the explicit input, else Cargo.toml. A repository without a
# crate has nothing to resolve — the input is the only source.
VERSION="${INPUT_VERSION:-}"
if [ -z "$VERSION" ]; then
  if [ ! -f Cargo.toml ]; then
    echo "::error::no Cargo.toml here and no version input — a non-crate repository must name the version to cut"
    exit 1
  fi
  resolve_crate "${INPUT_PACKAGE:-}"
  VERSION="$CRATE_VERSION"
fi
BRANCH="${INPUT_BRANCH_PREFIX:-release/v}${VERSION}"

# The branch guard runs first, before the changelog rewrite touches the tree.
# A missing origin counts as "does not exist" (scratch checkouts, dry runs).
if git ls-remote --exit-code origin "refs/heads/${BRANCH}" >/dev/null 2>&1; then
  echo "::error::${BRANCH} already exists"
  exit 1
fi

# One date for every surface the cut stamps. Resolved here and exported, so
# the changelog section and the citation file cannot disagree by a clock read
# either side of midnight UTC.
export INPUT_DATE="${INPUT_DATE:-$(date -u +%F)}"

# The sibling changelog action performs the cut: [Unreleased] becomes the
# released section for $VERSION, the compare link is rewritten, and
# CHANGELOG_VERSION lands in the job environment.
INPUT_MODE="cut" bash "$GITHUB_ACTION_PATH/../changelog/changelog.sh"

# The citation file, where the repository keeps one. CFF carries the released
# version and date as top-level keys and nothing else in the release derives
# them, so they go stale until a consumer's own gate catches it, one release
# late. An empty `citation` input disables this; a missing file skips it
# silently, so a repository without a CITATION.cff configures nothing.
CITATION="${INPUT_CITATION-CITATION.cff}"
CITATION_STAMPED=""
if [ -n "$CITATION" ] && [ -f "$CITATION" ]; then
  # Keys are matched anchored and whole-line, never by substituting the old
  # version string: `cff-version:` must survive a `version:` stamp, and a
  # dependency pinned at the outgoing version must not be rewritten.
  if grep -q '^version:' "$CITATION"; then
    sed -i "s|^version:.*|version: $VERSION|" "$CITATION"
    CITATION_STAMPED="version"
  else
    echo "::warning::$CITATION has no top-level \`version:\` to stamp"
  fi
  # `date-released` is optional in CFF, so it is updated only where the file
  # already keeps one. Adding a key the author omitted is their call, not ours.
  if grep -q '^date-released:' "$CITATION"; then
    sed -i "s|^date-released:.*|date-released: $INPUT_DATE|" "$CITATION"
    CITATION_STAMPED="${CITATION_STAMPED:+$CITATION_STAMPED, }date-released"
  fi
  if [ -n "$CITATION_STAMPED" ]; then
    echo "✓ stamped $CITATION_STAMPED in $CITATION"
  fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${VERSION}"
    echo "branch=${BRANCH}"
  } >>"$GITHUB_OUTPUT"
fi

if [ "${INPUT_DRY_RUN:-false}" = "true" ]; then
  echo "✓ dry run: would cut ${BRANCH} for ${VERSION} (cut in the working tree only)"
  exit 0
fi

# The default identity is the github-actions bot's canonical pair — 41898282
# is that account's user id, so GitHub attributes the commit to the bot. A
# machine-user or App identity (with a matching token) makes the merge-back
# pull request trigger CI, which events from the workflow token do not.
git config user.name "${INPUT_GIT_USER_NAME:-github-actions[bot]}"
git config user.email "${INPUT_GIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
git switch -c "${BRANCH}"
git add "${INPUT_CHANGELOG:-CHANGELOG.md}"
if [ -n "$CITATION_STAMPED" ]; then
  git add "$CITATION"
fi
git commit -m "chore: release v${VERSION}"
git push origin "${BRANCH}"

if [ "${INPUT_MERGE_BACK:-true}" = "true" ]; then
  BASE="${INPUT_BASE:-}"
  if [ -z "$BASE" ]; then
    BASE="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '.default_branch')"
  fi
  gh pr create --repo "${GITHUB_REPOSITORY}" --base "$BASE" --head "${BRANCH}" \
    --title "chore: release v${VERSION}" \
    --body "Merge-back of the release branch: the release commit for v${VERSION}. The release pipeline builds every push of this branch into the v${VERSION} draft pre-release."
fi

if [ -n "${INPUT_PIPELINE_WORKFLOW:-}" ]; then
  gh workflow run "${INPUT_PIPELINE_WORKFLOW}" --repo "${GITHUB_REPOSITORY}" --ref "${BRANCH}"
fi

echo "✓ cut ${BRANCH} for ${VERSION}"
