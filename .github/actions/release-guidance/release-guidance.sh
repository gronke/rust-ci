#!/usr/bin/env bash
# Write the release manager's next steps for a freshly built draft
# pre-release into the step summary (and the log). Inputs arrive as env vars
# from action.yml.
#   INPUT_VERSION     the version the draft carries (no leading "v")
#   INPUT_MARKER_TAG  the candidate marker tag of this build
#   INPUT_COMMIT      the commit the marker sealed
#   INPUT_TAG_SCRIPT  repository-relative tagging helper (else plain git tag)
#   INPUT_DRAFT_URL   draft release URL, linked when set
set -euo pipefail

VERSION="${INPUT_VERSION:?version is required}"
MARKER="${INPUT_MARKER_TAG:?marker-tag is required}"
COMMIT="${INPUT_COMMIT:?commit is required}"
TAG="v${VERSION}"

if [ -n "${INPUT_TAG_SCRIPT:-}" ]; then
  SIGN_COMMAND="${INPUT_TAG_SCRIPT} ${COMMIT} -s"
else
  SIGN_COMMAND="git tag -s ${TAG} ${COMMIT}"
fi

DRAFT_LINE=""
if [ -n "${INPUT_DRAFT_URL:-}" ]; then
  DRAFT_LINE="Review [the draft release](${INPUT_DRAFT_URL}) — assets and notes — before sealing."
fi

GUIDANCE="$(cat <<EOF
## Release candidate ready: ${TAG} (${MARKER})

The draft pre-release for ${TAG} was rebuilt from \`${COMMIT}\`, marked by \`${MARKER}\`.
Drafts are invisible and mutable, and marker tags reserve nothing — nothing is consumed until the signed final tag publishes the draft.
${DRAFT_LINE}

### Accept — seal and publish

Whoever holds a release-signing key registered with their GitHub account:

\`\`\`sh
git fetch origin 'refs/tags/${TAG}-rc*:refs/tags/${TAG}-rc*'
${SIGN_COMMAND}
git push origin ${TAG}
\`\`\`

The tag must be annotated, signed with a key GitHub can verify, and point at exactly \`${COMMIT}\` — the pipeline refuses anything else.
Push the tag by name; never \`git push --tags\`, which pushes every local tag along.

### Reject — nothing to unwind

Delete the draft release and the release branch; the marker tags reserve nothing and can stay or be deleted.
Or push a fix to the release branch instead: the next build refreshes the same draft as the following candidate.

### What the tag push triggers

The pipeline's final path runs the signature gate, asserts the tag seals the newest marker commit, attests and signs the assets where the repository is public, and the publish job flips the draft live.
Publication is the one irreversible step: a published release is immutable, and its tag name is consumed forever — even deleting the release does not free it.
EOF
)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$GUIDANCE" >>"$GITHUB_STEP_SUMMARY"
fi
printf '%s\n' "$GUIDANCE"
