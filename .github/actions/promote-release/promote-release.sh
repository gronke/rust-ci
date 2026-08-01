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
# an active signature rule covering the final tag means manual (a rule scoped
# to v*-sig companions does not), none means off, and unreadable rulesets mean
# manual — never push an unsigned tag on a repository whose policy is unknown.
MODE="${INPUT_SIGN_TAGS:-}"
if [ -z "$MODE" ]; then
  signature_rule_covers_ref "refs/tags/${TAG}"
  case "$SIGNATURE_RULE_VERDICT" in
    false) MODE="off" ;;
    true)
      MODE="manual"
      echo "::notice::an active tag ruleset requires signatures on ${TAG}; sign-tags resolves to manual"
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
# An explicit sign-tags: off must not collide with the repository's own policy:
# an unsigned ${TAG} that an active signature rule covers would be rejected at
# push time — or slip through a bypass and fail the gate after the release is
# live. The contradiction errors here, before anything is created.
signature_rule_covers_ref "refs/tags/${TAG}"
case "$SIGNATURE_RULE_VERDICT" in
  true)
    echo "::error::sign-tags: off, but an active tag ruleset requires signatures on ${TAG} — retarget the rule (e.g. to v*-sig companions) or use sign-tags: manual"
    exit 1
    ;;
  false) ;;
  *)
    echo "::warning::cannot read the tag rulesets to verify ${TAG} may be created unsigned; continuing"
    ;;
esac

git config user.name "$INPUT_GIT_USER_NAME"
git config user.email "$INPUT_GIT_USER_EMAIL"

# --- the moving major, decided first ---------------------------------------------
# Read-only, before anything is pushed: nothing about the decision can fail a
# promotion that is already live. The major advances only when the promoted
# version is the highest stable in its line — promoting a backport publishes
# the release and leaves the major alone. The target is the very commit this
# run promotes, so no separate provenance check applies.
MOVE_MAJOR="false" MAJOR=""
if [ "${INPUT_MOVING_MAJOR:-false}" = "true" ]; then
  case "$VERSION" in
    *-*) echo "prerelease; the moving major stays" ;;
    *)
      MAJOR="v${VERSION%%.*}"
      git fetch --tags --force --quiet origin
      MAJOR_HIGHEST="$({ git tag --list "${MAJOR}.*"; echo "v${VERSION}"; } | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
      if [ "$MAJOR_HIGHEST" = "v${VERSION}" ]; then
        MOVE_MAJOR="true"
      else
        echo "::notice::${MAJOR_HIGHEST} is newer than v${VERSION}; ${MAJOR} stays — a backport publishes without advancing the major"
      fi
      ;;
  esac
fi

# Idempotent re-run: a completed promotion's tag already points at this very
# commit — skip the push and proceed to the flip and the major, which are
# idempotent themselves. The same version on a different commit is a conflict,
# named as such.
EXISTING="$(git ls-remote origin "refs/tags/${TAG}" | head -1 | cut -f1)"
if [ -n "$EXISTING" ]; then
  git fetch --quiet origin "refs/tags/${TAG}:refs/tags/${TAG}" --no-tags --force
  EXISTING_COMMIT="$(git rev-list -n1 "refs/tags/${TAG}")"
  if [ "$EXISTING_COMMIT" != "$GITHUB_SHA" ]; then
    echo "::error::${TAG} already exists on ${EXISTING_COMMIT}, not ${GITHUB_SHA} — a different promotion owns this version"
    exit 1
  fi
  echo "::notice::${TAG} already exists on ${GITHUB_SHA}; skipping the tag push (idempotent re-run)"
else
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
fi

# A stable version sheds the --prerelease the draft was created with; semver's
# hyphen is the prerelease marker.
case "$VERSION" in
  *-*) gh release edit "$TAG" --draft=false ;;
  *) gh release edit "$TAG" --draft=false --prerelease=false ;;
esac
echo "✓ the ${TAG} release is published"

if [ "$MOVE_MAJOR" = "true" ]; then
  git push origin ":refs/tags/${MAJOR}" || true # delete the old tag (ignore if absent)
  git tag -f -a -m "${MAJOR} (moving major) -> ${TAG}" "$MAJOR" "$GITHUB_SHA"
  git push -f origin "refs/tags/${MAJOR}"
  echo "✓ ${MAJOR} advanced to ${TAG}"
fi

write_outputs "true" "off"
