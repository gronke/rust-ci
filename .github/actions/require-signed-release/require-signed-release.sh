#!/usr/bin/env bash
# Answer whether a release commit carries a human signature — the gate for
# registry publication. Unsigned is an answer, not an error: the workflow
# feeds `signed` into cargo-publish's `publish` input, so an unsigned release
# rehearses (--dry-run) instead of uploading. Inputs arrive as env vars from
# action.yml.
#   INPUT_VERSION                  the released version (no leading "v")
#   INPUT_TAG                      explicit release tag; default v<version>
#   INPUT_ATTESTATION_TAGS         glob another tag must match to count (default *)
#   INPUT_ACCEPT_RELEASE_TAG       "true": a verified-signed release tag satisfies
#   INPUT_ACCEPT_ATTESTATION_TAG   "true": a verified-signed tag on the same commit satisfies
#   INPUT_ACCEPT_SIGNED_COMMIT     "false": opt-in — a verified commit signature satisfies
#   INPUT_ACCEPT_WEB_FLOW          "false": GitHub's web-flow (UI merge) signature does not count
set -euo pipefail

TAG="${INPUT_TAG:-}"
if [ -z "$TAG" ]; then
  TAG="v${INPUT_VERSION:?version or tag is required}"
fi

write_outputs() { # signed source attestation commit
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "signed=$1"
      echo "source=$2"
      echo "attestation=$3"
      echo "commit=$4"
    } >>"$GITHUB_OUTPUT"
  fi
}

# --- the release tag and its commit ----------------------------------------------
REF="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${TAG}" 2>/dev/null)" || {
  echo "::error::release tag ${TAG} not found"
  exit 1
}
OBJ_SHA="$(jq -r '.object.sha' <<<"$REF")"
OBJ_TYPE="$(jq -r '.object.type' <<<"$REF")"

# One read per annotated tag object: the commit it seals and whether GitHub
# verifies its signature.
tag_object() { # <tag-object-sha> — prints "<commit>\t<verified>"
  gh api "repos/${GITHUB_REPOSITORY}/git/tags/$1" 2>/dev/null \
    | jq -r '[.object.sha, (.verification.verified // false | tostring)] | @tsv'
}

if [ "$OBJ_TYPE" = "tag" ]; then
  IFS=$'\t' read -r COMMIT RELEASE_VERIFIED < <(tag_object "$OBJ_SHA") || {
    echo "::error::cannot read the ${TAG} tag object"
    exit 1
  }
else
  COMMIT="$OBJ_SHA" RELEASE_VERIFIED="false" # a lightweight tag carries no signature
fi

# --- 1: the release tag itself ----------------------------------------------------
if [ "${INPUT_ACCEPT_RELEASE_TAG:-true}" = "true" ] && [ "$RELEASE_VERIFIED" = "true" ]; then
  echo "✓ ${TAG} is a verified signed tag on ${COMMIT}"
  write_outputs true release-tag "" "$COMMIT"
  exit 0
fi

# --- 2: an attestation tag on the same commit --------------------------------------
# Lightweight tags cannot be signed and are skipped; narrowing the glob (e.g.
# v*-sig) keeps the per-candidate reads few on tag-heavy repositories.
if [ "${INPUT_ACCEPT_ATTESTATION_TAG:-true}" = "true" ]; then
  GLOB="${INPUT_ATTESTATION_TAGS:-*}"
  while IFS=$'\t' read -r A_SHA A_TYPE A_REF; do
    [ -n "$A_REF" ] || continue
    NAME="${A_REF#refs/tags/}"
    [ "$NAME" = "$TAG" ] && continue
    # shellcheck disable=SC2254  # the glob must glob
    case "$NAME" in $GLOB) ;; *) continue ;; esac
    [ "$A_TYPE" = "tag" ] || continue
    IFS=$'\t' read -r A_COMMIT A_VERIFIED < <(tag_object "$A_SHA") || continue
    [ "$A_COMMIT" = "$COMMIT" ] || continue
    if [ "$A_VERIFIED" = "true" ]; then
      echo "✓ ${NAME} is a verified signed tag on the release commit ${COMMIT}"
      write_outputs true attestation-tag "$NAME" "$COMMIT"
      exit 0
    fi
  done < <(gh api --paginate "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags/" 2>/dev/null \
    | jq -rs 'add // [] | .[] | [.object.sha, .object.type, .ref] | @tsv')
fi

# --- 3 (opt-in): the commit's own signature ----------------------------------------
# GitHub signs UI-made rebase/squash merges with its own web-flow key, which
# would satisfy this check on virtually every UI-merged commit — so web-flow
# does not count unless explicitly accepted.
if [ "${INPUT_ACCEPT_SIGNED_COMMIT:-false}" = "true" ]; then
  C="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${COMMIT}" 2>/dev/null || true)"
  C_VERIFIED="$(jq -r '.commit.verification.verified // false' <<<"$C")"
  C_COMMITTER="$(jq -r '.committer.login // ""' <<<"$C")"
  if [ "$C_VERIFIED" = "true" ]; then
    if [ "$C_COMMITTER" = "web-flow" ] && [ "${INPUT_ACCEPT_WEB_FLOW:-false}" != "true" ]; then
      echo "::notice::${COMMIT} is signed by GitHub's web-flow key (a UI merge); not counted — set accept-web-flow to accept it"
    else
      echo "✓ commit ${COMMIT} carries a verified signature"
      write_outputs true commit "" "$COMMIT"
      exit 0
    fi
  fi
fi

echo "::notice::no verified signature for ${TAG} on ${COMMIT} — sign the release tag, push a signed tag on that commit, or (opt-in) sign the commit; until then the registry step rehearses instead of uploading"
write_outputs false "" "" "$COMMIT"
