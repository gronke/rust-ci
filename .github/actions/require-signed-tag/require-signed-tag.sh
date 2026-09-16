#!/usr/bin/env bash
# Verify that a tag is an annotated tag object with a GitHub-verified
# signature, through the API; no keyring on the runner. This is the release
# pipeline's signature gate: a tag ruleset restricts who creates release tags,
# it does not verify a tag's signature. Inputs arrive as env vars from
# action.yml.
#   INPUT_TAG        the tag name (else derived from a refs/tags/* GITHUB_REF)
#   INPUT_WARN_ONLY  "true" warns instead of failing on signature refusals
set -euo pipefail

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
  refuse "${TAG} is a lightweight tag; release tags must be annotated and signed. If it came from publishing the draft in the web UI, the immutable release has locked it and the version is spent: leave the release as it is and take the next version through the flow (docs/release-flow.md, When a gate refuses)" "$SHA" "lightweight"
fi

OBJ="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${SHA}")"
VERIFIED="$(printf '%s' "$OBJ" | jq -r '.verification.verified')"
REASON="$(printf '%s' "$OBJ" | jq -r '.verification.reason')"
COMMIT="$(printf '%s' "$OBJ" | jq -r '.object.sha')"

if [ "$VERIFIED" != "true" ]; then
  refuse "${TAG} is not a verified signed tag (reason: ${REASON}); only signed tags may be released" "$COMMIT" "$REASON"
fi

write_outputs "true" "$COMMIT" "$REASON"
echo "✓ ${TAG} is an annotated tag with a GitHub-verified signature (${REASON}), sealing ${COMMIT}"
