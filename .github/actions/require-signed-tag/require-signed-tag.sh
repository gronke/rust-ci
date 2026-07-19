#!/usr/bin/env bash
# Verify that a tag is an annotated tag object with a GitHub-verified
# signature, through the API — no keyring on the runner. Inputs arrive as env
# vars from action.yml.
#   INPUT_TAG  the tag name (else derived from a refs/tags/* GITHUB_REF)
set -euo pipefail

TAG="${INPUT_TAG:-}"
if [ -z "$TAG" ]; then
  case "${GITHUB_REF:-}" in
    refs/tags/*) TAG="${GITHUB_REF#refs/tags/}" ;;
    *)
      echo "::error::no tag input and the ref (${GITHUB_REF:-unset}) is not a tag push"
      exit 1
      ;;
  esac
fi

REF_JSON="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${TAG}")"
TYPE="$(printf '%s' "$REF_JSON" | jq -r '.object.type')"
if [ "$TYPE" != "tag" ]; then
  echo "::error::${TAG} is a lightweight tag; release tags must be annotated and signed"
  exit 1
fi

SHA="$(printf '%s' "$REF_JSON" | jq -r '.object.sha')"
OBJ="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${SHA}")"
VERIFIED="$(printf '%s' "$OBJ" | jq -r '.verification.verified')"
REASON="$(printf '%s' "$OBJ" | jq -r '.verification.reason')"
COMMIT="$(printf '%s' "$OBJ" | jq -r '.object.sha')"

if [ "$VERIFIED" != "true" ]; then
  echo "::error::${TAG} is not a verified signed tag (reason: ${REASON}); only signed tags may be released"
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "commit=${COMMIT}"
    echo "reason=${REASON}"
  } >>"$GITHUB_OUTPUT"
fi
echo "✓ ${TAG} is an annotated tag with a GitHub-verified signature (${REASON}), sealing ${COMMIT}"
