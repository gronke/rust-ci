#!/usr/bin/env bash
# Verify that a tag is an annotated tag object with a GitHub-verified
# signature, through the API — no keyring on the runner. Requiring the
# signature is the workflow's preference; the repository's tag ruleset is the
# enforcement, and the two are checked for alignment. Inputs arrive as env
# vars from action.yml.
#   INPUT_TAG            the tag name (else derived from a refs/tags/* GITHUB_REF)
#   INPUT_WARN_ONLY      "true" warns instead of failing on signature refusals
#   INPUT_CHECK_RULESET  "true" warns when no active tag ruleset requires signatures
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/tag-rulesets.sh"

TAG="${INPUT_TAG:-}"
if [ -z "$TAG" ]; then
  case "${GITHUB_REF:-}" in
    refs/tags/*) TAG="${GITHUB_REF#refs/tags/}" ;;
    *)
      # A non-tag ref is a workflow wiring mistake, not a signature preference:
      # it fails regardless of warn-only.
      echo "::error::no tag input and the ref (${GITHUB_REF:-unset}) is not a tag push"
      exit 1
      ;;
  esac
fi

write_outputs() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "verified=$1"
      echo "commit=$2"
      echo "reason=$3"
    } >>"$GITHUB_OUTPUT"
  fi
}

refuse() {
  if [ "${INPUT_WARN_ONLY:-false}" = "true" ]; then
    echo "::warning::$1"
    write_outputs "false" "$2" "$3"
    exit 0
  fi
  echo "::error::$1"
  exit 1
}

REF_JSON="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${TAG}")"
TYPE="$(printf '%s' "$REF_JSON" | jq -r '.object.type')"
SHA="$(printf '%s' "$REF_JSON" | jq -r '.object.sha')"
if [ "$TYPE" != "tag" ]; then
  refuse "${TAG} is a lightweight tag; release tags must be annotated and signed" "$SHA" "lightweight"
fi

OBJ="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${SHA}")"
VERIFIED="$(printf '%s' "$OBJ" | jq -r '.verification.verified')"
REASON="$(printf '%s' "$OBJ" | jq -r '.verification.reason')"
COMMIT="$(printf '%s' "$OBJ" | jq -r '.object.sha')"

if [ "$VERIFIED" != "true" ]; then
  refuse "${TAG} is not a verified signed tag (reason: ${REASON}); only signed tags may be released" "$COMMIT" "$REASON"
fi

# Alignment: the gate refuses builds, but only a repository tag ruleset can
# prevent an unsigned tag from existing. When the workflow enforces (not
# warn-only), warn if no active tag ruleset requires signatures. A token that
# cannot read the rulesets skips the check quietly.
if [ "${INPUT_CHECK_RULESET:-true}" = "true" ] && [ "${INPUT_WARN_ONLY:-false}" != "true" ]; then
  case "$(signature_tag_ruleset_active)" in
    true) ;;
    false)
      echo "::warning::the workflow requires a signed tag, but no active tag ruleset requires signatures — the gate refuses builds, it cannot prevent an unsigned tag from existing; add a tag ruleset with required signatures to align the repository with this preference"
      ;;
    *)
      echo "::notice::could not read the repository rulesets to verify signature-rule alignment; skipping"
      ;;
  esac
fi

write_outputs "true" "$COMMIT" "$REASON"
echo "✓ ${TAG} is an annotated tag with a GitHub-verified signature (${REASON}), sealing ${COMMIT}"
