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

DRAFT_LINE=""
if [ -n "${INPUT_DRAFT_URL:-}" ]; then
  DRAFT_LINE="Review [the draft release](${INPUT_DRAFT_URL}), assets and notes, before signing."
fi

if [ -n "${INPUT_TAG_SCRIPT:-}" ]; then
  SIGN_COMMAND="${INPUT_TAG_SCRIPT} ${COMMIT} -s"
else
  # The signed final tag copies the candidate marker's message (the rendered
  # changelog section), so accepting is a pure-git two-liner with no message
  # to retype.
  SIGN_COMMAND="git tag -s -F <(git tag -l --format='%(contents)' ${MARKER}) ${TAG} ${COMMIT}"
fi

GUIDANCE="$(cat <<EOF
## Release candidate ready: ${TAG} (${MARKER})

The draft pre-release for ${TAG} was rebuilt from \`${COMMIT}\`, marked by \`${MARKER}\`.
Drafts are invisible and mutable, and marker tags reserve nothing; nothing is consumed until the signed final tag publishes the draft.
${DRAFT_LINE}

### Accept: sign and push the tag

Whoever holds a release-signing key registered with their GitHub account:

\`\`\`sh
git fetch origin 'refs/tags/${TAG}-rc*:refs/tags/${TAG}-rc*'
${SIGN_COMMAND}
git push origin ${TAG}
\`\`\`

The tag must be annotated, signed with a key GitHub can verify, and carry exactly \`${COMMIT}\`'s content; a rebase-merged merge-back's tip has the identical tree and passes the seal too.
Its message is copied from the marker \`${MARKER}\`, the changelog section rendered for ${TAG}.
Push the tag by name; never \`git push --tags\`, which pushes every local tag along.

### Reject: nothing to unwind

Delete the draft release and the release branch; the marker tags reserve nothing and can stay or be deleted.
Or push a fix to the release branch instead: the next build refreshes the same draft as the following candidate.

### What the tag push triggers

The tag run gates on the signature (\`require-signed-tag\`), seals the tag against the newest marker by tree, flips the draft live, advances the moving major, and, for a crate, uploads it to the registry behind the gate.
Publication is the one irreversible step: a published release is immutable, and its tag name is consumed forever (deleting the release does not free it).
Never publish the draft by hand: GitHub would create an unsigned tag that fails the gate after the release is already live.
EOF
)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$GUIDANCE" >>"$GITHUB_STEP_SUMMARY"
fi
printf '%s\n' "$GUIDANCE"
