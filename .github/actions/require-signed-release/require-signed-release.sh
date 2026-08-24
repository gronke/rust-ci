#!/usr/bin/env bash
# Answer whether a release commit carries a human signature — the gate for
# registry publication. Unsigned is an answer, not an error: the workflow
# feeds `signed` into cargo-publish's `publish` input, so an unsigned release
# rehearses (--dry-run) instead of uploading. Inputs arrive as env vars from
# action.yml.
#   INPUT_VERSION                  the released version (no leading "v")
#   INPUT_TAG                      explicit release tag; default v<version>
#   INPUT_ATTESTATION_TAG          a pushed companion; the release it seals is derived from it
#   INPUT_REQUIRE_PUBLISHED        "true": a draft (or absent) release is an error
#   INPUT_ATTESTATION_TAGS         glob another tag must match to count (default *)
#   INPUT_ACCEPT_RELEASE_TAG       "true": a verified-signed release tag satisfies
#   INPUT_ACCEPT_ATTESTATION_TAG   "true": a verified-signed tag on the same commit satisfies
#   INPUT_ACCEPT_SIGNED_COMMIT     "false": opt-in — a verified commit signature satisfies
#   INPUT_ACCEPT_WEB_FLOW          "false": GitHub's web-flow (UI merge) signature does not count
set -euo pipefail

write_outputs() { # signed source attestation commit release-tag
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "signed=$1"
      echo "source=$2"
      echo "attestation=$3"
      echo "commit=$4"
      echo "release-tag=$5"
      echo "version=${5#v}"
    } >>"$GITHUB_OUTPUT"
  fi
}

# --- reading tags --------------------------------------------------------------------
declare -A _TAG_TARGET=() _TAG_VERIFIED=()

# The commit a tag seals and whether GitHub verifies its signature, memoized:
# the derivation and the companion scan ask about the same tags. Sets
# TAG_COMMIT and TAG_VERIFIED.
resolve_tag() { # <name> <object-sha> <object-type>
  local name="$1" sha="$2" type="$3" row raw
  if [ -z "${_TAG_TARGET[$name]:-}" ]; then
    if [ "$type" = "tag" ]; then
      # gh's own status decides, so jq runs on the captured body rather than
      # in a pipeline that would swallow a failed read.
      raw="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${sha}" 2>/dev/null)" || return 1
      row="$(jq -r '[.object.sha, (.verification.verified // false | tostring)] | @tsv' <<<"$raw")"
    else
      row="$(printf '%s\tfalse' "$sha")" # a lightweight tag carries no signature
    fi
    _TAG_TARGET[$name]="${row%%$'\t'*}"
    _TAG_VERIFIED[$name]="${row##*$'\t'}"
  fi
  TAG_COMMIT="${_TAG_TARGET[$name]}"
  TAG_VERIFIED="${_TAG_VERIFIED[$name]}"
}

# Every tag ref in the repository, once: "<name>\t<object-sha>\t<object-type>".
_ALL_TAG_REFS=""
all_tag_refs() {
  if [ -z "$_ALL_TAG_REFS" ]; then
    _ALL_TAG_REFS="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/git/matching-refs/tags/" 2>/dev/null \
      | jq -rs 'add // [] | .[] | [(.ref | sub("^refs/tags/"; "")), .object.sha, .object.type] | @tsv')"
  fi
  # A trailing newline is load-bearing: `read` discards a final partial line,
  # which would silently drop the last tag in the repository.
  printf '%s\n' "$_ALL_TAG_REFS"
}

# Only published releases are reachable by tag name; a draft reserves nothing.
release_state() { # <tag> — prints "published" | "draft" | "none"
  if gh api "repos/${GITHUB_REPOSITORY}/releases/tags/$1" >/dev/null 2>&1; then
    printf 'published'
  elif [ "$(gh release view "$1" --json isDraft --jq .isDraft 2>/dev/null || true)" = "true" ]; then
    printf 'draft'
  else
    printf 'none'
  fi
}

# --- which release is being gated ------------------------------------------------------
TAG="${INPUT_TAG:-}"
ATTESTATION_TAG="${INPUT_ATTESTATION_TAG:-}"

if [ -n "$ATTESTATION_TAG" ]; then
  # Derive the release from the companion by commit identity rather than by
  # name: which suffix (or prefix) a repository attests with is its own
  # business, and the commit is what both tags agree on.
  A_REF="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${ATTESTATION_TAG}" 2>/dev/null)" || {
    echo "::error::attestation tag ${ATTESTATION_TAG} not found"
    exit 1
  }
  resolve_tag "$ATTESTATION_TAG" "$(jq -r '.object.sha' <<<"$A_REF")" "$(jq -r '.object.type' <<<"$A_REF")" || {
    echo "::error::cannot read the ${ATTESTATION_TAG} tag object"
    exit 1
  }
  COMMIT="$TAG_COMMIT"

  published=() drafted=()
  while IFS=$'\t' read -r name sha type; do
    { [ -n "$name" ] && [ "$name" != "$ATTESTATION_TAG" ]; } || continue
    resolve_tag "$name" "$sha" "$type" || continue
    [ "$TAG_COMMIT" = "$COMMIT" ] || continue
    case "$(release_state "$name")" in
      published) published+=("$name") ;;
      draft) drafted+=("$name") ;;
    esac
  done < <(all_tag_refs)

  case "${#published[@]}" in
    1) TAG="${published[0]}" ;;
    0)
      if [ "${#drafted[@]}" -gt 0 ]; then
        echo "::error::the release for ${drafted[*]} on ${COMMIT} is still a draft — publish it first; a signature completes automation, it does not publish drafts"
      else
        echo "::error::${ATTESTATION_TAG} seals ${COMMIT}, which carries no published release — nothing to attest"
      fi
      exit 1
      ;;
    *)
      echo "::error::${COMMIT} carries more than one published release (${published[*]}); name the intended one with the tag input"
      exit 1
      ;;
  esac
  echo "${ATTESTATION_TAG} seals ${TAG} (${COMMIT})"
else
  [ -n "$TAG" ] || TAG="v${INPUT_VERSION:?version, tag or attestation-tag is required}"
  REF="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${TAG}" 2>/dev/null)" || {
    echo "::error::release tag ${TAG} not found"
    exit 1
  }
  resolve_tag "$TAG" "$(jq -r '.object.sha' <<<"$REF")" "$(jq -r '.object.type' <<<"$REF")" || {
    echo "::error::cannot read the ${TAG} tag object"
    exit 1
  }
  COMMIT="$TAG_COMMIT"
fi

if [ "${INPUT_REQUIRE_PUBLISHED:-false}" = "true" ]; then
  case "$(release_state "$TAG")" in
    published) ;;
    draft)
      echo "::error::the ${TAG} release is still a draft — publish it first"
      exit 1
      ;;
    *)
      echo "::error::no release exists for ${TAG}"
      exit 1
      ;;
  esac
fi

# --- 1: the release tag itself ------------------------------------------------------
RELEASE_VERIFIED="${_TAG_VERIFIED[$TAG]:-false}"
if [ "${INPUT_ACCEPT_RELEASE_TAG:-true}" = "true" ] && [ "$RELEASE_VERIFIED" = "true" ]; then
  echo "✓ ${TAG} is a verified signed tag on ${COMMIT}"
  write_outputs true release-tag "" "$COMMIT" "$TAG"
  exit 0
fi

# --- 2: an attestation tag on the same commit ----------------------------------------
# Lightweight tags cannot be signed and are skipped; narrowing the glob (e.g.
# v*-sig) keeps the per-candidate reads few on tag-heavy repositories.
if [ "${INPUT_ACCEPT_ATTESTATION_TAG:-true}" = "true" ]; then
  GLOB="${INPUT_ATTESTATION_TAGS:-*}"
  while IFS=$'\t' read -r name sha type; do
    { [ -n "$name" ] && [ "$name" != "$TAG" ]; } || continue
    # shellcheck disable=SC2254  # the glob must glob
    case "$name" in $GLOB) ;; *) continue ;; esac
    [ "$type" = "tag" ] || continue
    resolve_tag "$name" "$sha" "$type" || continue
    [ "$TAG_COMMIT" = "$COMMIT" ] || continue
    if [ "$TAG_VERIFIED" = "true" ]; then
      echo "✓ ${name} is a verified signed tag on the release commit ${COMMIT}"
      write_outputs true attestation-tag "$name" "$COMMIT" "$TAG"
      exit 0
    fi
  done < <(all_tag_refs)
fi

# --- 3 (opt-in): the commit's own signature ------------------------------------------
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
      write_outputs true commit "" "$COMMIT" "$TAG"
      exit 0
    fi
  fi
fi

echo "::notice::no verified signature for ${TAG} on ${COMMIT} — sign the release tag, push a signed tag on that commit, or (opt-in) sign the commit; until then the registry step rehearses instead of uploading"

# Opt-in: put the way forward where the release manager is already
# looking, with the companion's name derived from the attestation glob.
if [ "${INPUT_UNSIGNED_GUIDANCE:-false}" = "true" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  GLOB="${INPUT_ATTESTATION_TAGS:-*}"
  if [ "$GLOB" = "*" ]; then
    COMPANION="${TAG}-sig"
  else
    COMPANION="${GLOB/\*/${TAG#v}}"
  fi
  {
    echo "**Rehearsal only**: no verified signature covers \`${TAG}\` on \`${COMMIT}\`."
    echo ""
    echo "To publish, sign and push the companion on the release commit:"
    echo ""
    echo '```sh'
    echo "git fetch origin tag ${TAG}"
    echo "git tag -s -m '${TAG}' ${COMPANION} ${COMMIT}"
    echo "git push origin ${COMPANION}"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

write_outputs false "" "" "$COMMIT" "$TAG"
