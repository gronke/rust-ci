#!/usr/bin/env bash
# Promote a candidate from within the pipeline, or defer to the release
# manager — governed by sign-tags. Inputs arrive as env vars from action.yml;
# git and gh run in the step's working-directory.
#   INPUT_VERSION        the version being released (no leading "v")
#   INPUT_MARKER_TAG     the candidate marker this build created
#   INPUT_SIGN_TAGS      "manual" | "off" | "" (auto-detect from the tag rulesets)
#   INPUT_MOVING_MAJOR   "true" advances the moving v<MAJOR> tag after promotion
#   INPUT_GIT_USER_NAME  committer identity for the promoted tag
#   INPUT_GIT_USER_EMAIL committer email for the promoted tag
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/tag-rulesets.sh"

VERSION="$INPUT_VERSION"
MARKER="$INPUT_MARKER_TAG"
TAG="v${VERSION}"

write_outputs() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "promoted=$1"
      echo "mode=$2"
    } >>"$GITHUB_OUTPUT"
  fi
}

# --- the effective mode --------------------------------------------------------
# The explicit input wins; otherwise the repository's own enforcement decides:
# an active signature-requiring tag ruleset means manual, none means off, and
# unreadable rulesets mean manual — never push an unsigned tag on a repository
# whose policy is unknown.
MODE="${INPUT_SIGN_TAGS:-}"
if [ -z "$MODE" ]; then
  case "$(signature_tag_ruleset_active)" in
    false) MODE="off" ;;
    true)
      MODE="manual"
      echo "::notice::an active tag ruleset requires signatures; sign-tags resolves to manual"
      ;;
    *)
      MODE="manual"
      echo "::notice::the tag rulesets are not readable with this token; sign-tags resolves to manual"
      ;;
  esac
fi
case "$MODE" in
  manual|off) ;;
  *)
    echo "::error::sign-tags must be 'manual', 'off', or empty (got '${MODE}')"
    exit 1
    ;;
esac

if [ "$MODE" = "manual" ]; then
  echo "sign-tags: manual — the release manager signs and pushes ${TAG}; the guidance above has the commands"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "**sign-tags: manual** — the release manager signs and pushes \`${TAG}\`; the guidance above has the commands." >>"$GITHUB_STEP_SUMMARY"
  fi
  write_outputs "false" "manual"
  exit 0
fi

# --- off: the pipeline promotes ------------------------------------------------
git config user.name "$INPUT_GIT_USER_NAME"
git config user.email "$INPUT_GIT_USER_EMAIL"

# The final tag carries the marker's message (the rendered release notes).
git fetch --quiet origin "refs/tags/${MARKER}:refs/tags/${MARKER}" --no-tags --force
MESSAGE_FILE="$(mktemp)"
git tag -l --format='%(contents)' "$MARKER" >"$MESSAGE_FILE"
if ! grep -q '[^[:space:]]' "$MESSAGE_FILE"; then
  echo "${TAG}" >"$MESSAGE_FILE"
fi
git tag -a -F "$MESSAGE_FILE" "$TAG" "$GITHUB_SHA"
git push origin "refs/tags/${TAG}" || {
  echo "::error::the ${TAG} push was rejected (GH013) — with sign-tags off the tag ruleset must let Actions create final v* tags, or switch to sign-tags: manual and let the release manager sign"
  exit 1
}
echo "✓ ${TAG} promoted on ${GITHUB_SHA} with the marker's message"

gh release edit "$TAG" --draft=false
echo "✓ the ${TAG} release is published"

if [ "${INPUT_MOVING_MAJOR:-false}" = "true" ]; then
  case "$VERSION" in
    *-*) echo "prerelease; the moving major stays" ;;
    *)
      MAJOR="v${VERSION%%.*}"
      git tag -f -a -m "${MAJOR} (moving major) -> ${TAG}" "$MAJOR" "$GITHUB_SHA"
      git push -f origin "refs/tags/${MAJOR}"
      echo "✓ ${MAJOR} advanced to ${TAG}"
      ;;
  esac
fi

write_outputs "true" "off"
