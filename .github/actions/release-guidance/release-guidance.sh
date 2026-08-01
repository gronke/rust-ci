#!/usr/bin/env bash
# Write the release manager's next steps for a freshly built draft
# pre-release into the step summary (and the log). Inputs arrive as env vars
# from action.yml.
#   INPUT_VERSION     the version the draft carries (no leading "v")
#   INPUT_MARKER_TAG  the candidate marker tag of this build
#   INPUT_COMMIT      the commit the marker sealed
#   INPUT_GO_LIVE     "signed-tag" (default) or "publish-draft"
#   INPUT_TAG_SCRIPT  repository-relative tagging helper (else plain git tag)
#   INPUT_DRAFT_URL   draft release URL, linked when set
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/tag-rulesets.sh"

VERSION="${INPUT_VERSION:?version is required}"
MARKER="${INPUT_MARKER_TAG:?marker-tag is required}"
COMMIT="${INPUT_COMMIT:?commit is required}"
TAG="v${VERSION}"

GO_LIVE="${INPUT_GO_LIVE:-signed-tag}"
case "$GO_LIVE" in
  signed-tag | publish-draft) ;;
  *)
    echo "::error::go-live must be 'signed-tag' or 'publish-draft' (got '${GO_LIVE}')"
    exit 1
    ;;
esac

# publish-draft: publishing will make GitHub create ${TAG} unsigned on main's
# tip. A signature rule still covering it means that tag gets rejected — or
# slips through an admin bypass and fails the gate after the immutable
# publish. The misalignment errors here, at candidate time.
if [ "$GO_LIVE" = "publish-draft" ]; then
  signature_rule_covers_ref "refs/tags/${TAG}"
  case "$SIGNATURE_RULE_VERDICT" in
    true)
      echo "::error::go-live: publish-draft, but an active tag ruleset requires signatures on ${TAG} — retarget the rule (e.g. to v*-sig companions) or use go-live: signed-tag"
      exit 1
      ;;
    false) ;;
    *)
      echo "::warning::cannot read the tag rulesets to verify the publish-created ${TAG} will be accepted; continuing"
      ;;
  esac
fi

if [ "$GO_LIVE" = "publish-draft" ]; then
  CONSUMED="nothing is consumed until the draft is published."
  DRAFT_LINE=""
  if [ -n "${INPUT_DRAFT_URL:-}" ]; then
    DRAFT_LINE="Review [the draft release](${INPUT_DRAFT_URL}) — assets and notes — before publishing."
  fi
  # Publishing creates the tag from the release's target_commitish, so the
  # target is the whole game: pinned to the merged commit, the tag lands on the
  # content the marker sealed and no later push can move it.
  DEFAULT_BRANCH="$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch 2>/dev/null || echo main)"
  ACCEPT="$(cat <<EOF
### Accept — merge, then publish

1. Merge the merge-back pull request.
2. Publish the draft with its target pinned to the merged commit:

   \`\`\`sh
   target=\$(git ls-remote origin refs/heads/${DEFAULT_BRANCH} | cut -f1)
   gh release edit ${TAG} --draft=false --prerelease=false --target "\$target"
   \`\`\`

   The tag is created from the target, so the resolved SHA — the merge-back's commit — is what ${TAG} seals; a later push to ${DEFAULT_BRANCH} cannot move it.
   Publishing from the web dialog does the same, as long as the target there names that commit rather than the branch.
3. Optionally attest the release commit with your signature:

   \`\`\`sh
   git fetch origin 'refs/tags/${TAG}:refs/tags/${TAG}'
   git tag -s -m "${TAG}" ${TAG}-sig ${TAG}^{}
   git push origin refs/tags/${TAG}-sig
   \`\`\`
EOF
)"
  TRIGGERS="$(cat <<EOF
### What publishing triggers

The tag GitHub creates on publish runs the pipeline's final path: version coherence, the tree seal against the newest marker, and the moving major advancing.
Publication is the one irreversible step: a published release is immutable, and its tag name is consumed forever — even deleting the release does not free it.
Which is why the target is pinned: the seal then passes by construction, rather than depending on how long the click took.
EOF
)"
else
  CONSUMED="nothing is consumed until the signed final tag publishes the draft."
  DRAFT_LINE=""
  if [ -n "${INPUT_DRAFT_URL:-}" ]; then
    DRAFT_LINE="Review [the draft release](${INPUT_DRAFT_URL}) — assets and notes — before sealing."
  fi
  if [ -n "${INPUT_TAG_SCRIPT:-}" ]; then
    SIGN_COMMAND="${INPUT_TAG_SCRIPT} ${COMMIT} -s"
  else
    # Copy the candidate marker's message (the rendered changelog section) into the
    # signed final tag, so promoting is a pure-git two-liner — no message to retype.
    SIGN_COMMAND="git tag -s -F <(git tag -l --format='%(contents)' ${MARKER}) ${TAG} ${COMMIT}"
  fi
  ACCEPT="$(cat <<EOF
### Accept — seal and publish

Whoever holds a release-signing key registered with their GitHub account:

\`\`\`sh
git fetch origin 'refs/tags/${TAG}-rc*:refs/tags/${TAG}-rc*'
${SIGN_COMMAND}
git push origin ${TAG}
\`\`\`

The tag must be annotated, signed with a key GitHub can verify, and carry exactly \`${COMMIT}\`'s content — a rebase-merged merge-back's tip has the identical tree and passes the seal too.
Its message is copied from the marker \`${MARKER}\` — the changelog section rendered for ${TAG}.
Push the tag by name; never \`git push --tags\`, which pushes every local tag along.
EOF
)"
  TRIGGERS="$(cat <<EOF
### What the tag push triggers

The pipeline's final path runs the signature gate, asserts the tag seals the newest marker commit, attests and signs the assets where the repository is public, and the publish job flips the draft live.
Publication is the one irreversible step: a published release is immutable, and its tag name is consumed forever — even deleting the release does not free it.
Never publish the draft by hand — the pipeline flips it; a hand-published draft makes GitHub create an unsigned tag that fails this gate after the release is already live.
EOF
)"
fi

GUIDANCE="$(cat <<EOF
## Release candidate ready: ${TAG} (${MARKER})

The draft pre-release for ${TAG} was rebuilt from \`${COMMIT}\`, marked by \`${MARKER}\`.
Drafts are invisible and mutable, and marker tags reserve nothing — ${CONSUMED}
${DRAFT_LINE}

${ACCEPT}

### Reject — nothing to unwind

Delete the draft release and the release branch; the marker tags reserve nothing and can stay or be deleted.
Or push a fix to the release branch instead: the next build refreshes the same draft as the following candidate.

${TRIGGERS}
EOF
)"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$GUIDANCE" >>"$GITHUB_STEP_SUMMARY"
fi
printf '%s\n' "$GUIDANCE"
