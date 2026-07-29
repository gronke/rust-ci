#!/usr/bin/env bash
# Publish the crate to crates.io, or rehearse with --dry-run. Inputs arrive as
# env vars from action.yml; cargo runs in the step's working-directory.
#   INPUT_PUBLISH                  "true" uploads; anything else is a dry run
#   INPUT_TAG_PATTERN              regex v<version> must match to be published (empty ⇒ any)
#   INPUT_REGISTRY_TOKEN           crates.io API token (empty ⇒ use the environment's)
#   INPUT_PACKAGE                  package name (required for a multi-member workspace)
#   INPUT_LOCKED                   "true" passes --locked
#   INPUT_ALLOW_ALREADY_PUBLISHED  "true" turns an already-published version into a skip
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/crate-version.sh"

write_outputs() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "published=$1"
      echo "version=${2:-}"
      echo "already-published=$3"
    } >>"$GITHUB_OUTPUT"
  fi
}

resolve_crate "${INPUT_PACKAGE:-}"
NAME="$CRATE_NAME" VERSION="$CRATE_VERSION" PUBLISHABLE="$CRATE_PUBLISHABLE"
echo "crate: $NAME  version: $VERSION  publishable-to-crates.io: $PUBLISHABLE"

# The manifest has the last word: `publish = false` means this crate is not for
# crates.io, and no input overrides that.
if [ "$PUBLISHABLE" != "true" ]; then
  echo "::notice::${NAME} declares publish = false; nothing to publish"
  write_outputs false "$VERSION" false
  exit 0
fi

args=()
[ -n "${INPUT_PACKAGE:-}" ] && args+=(-p "$NAME")
[ "${INPUT_LOCKED:-true}" = "true" ] && args+=(--locked)

# --- rehearsal ----------------------------------------------------------------
# The default. No credential is read, so a dry run cannot upload by accident.
case "${INPUT_PUBLISH:-false}" in
  1 | true | yes | on) ;;
  *)
    echo "::group::cargo publish --dry-run"
    cargo publish --dry-run "${args[@]}"
    echo "::endgroup::"
    echo "✓ ${NAME} ${VERSION} packages cleanly (dry run; nothing uploaded)"
    write_outputs false "$VERSION" false
    exit 0
    ;;
esac

# --- what may be published ---------------------------------------------------
# The dry run above is deliberately exempt: a candidate still rehearses
# packaging in full. This governs what reaches the registry. The pattern is
# tested against v<version> — the release gate has already asserted the tag is
# exactly that — so the check needs no ref context and works on a `release`
# event, a tag push and a dispatch alike.
PATTERN="${INPUT_TAG_PATTERN-}"
if [ -n "$PATTERN" ] && ! printf 'v%s' "$VERSION" | grep -Eq "$PATTERN"; then
  echo "::notice::v${VERSION} does not match ${PATTERN}; not publishing (prereleases and bare majors are excluded by the default pattern)"
  write_outputs false "$VERSION" false
  exit 0
fi

# --- the credential -----------------------------------------------------------
# Trusted Publishing (rust-lang/crates-io-auth-action) exports a short-lived
# CARGO_REGISTRY_TOKEN; the input is the classic-token fallback.
TOKEN="${INPUT_REGISTRY_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN="${CARGO_REGISTRY_TOKEN:-}"
  [ -n "$TOKEN" ] && echo "using the CARGO_REGISTRY_TOKEN already in the environment"
else
  echo "::add-mask::$TOKEN"
fi
if [ -z "$TOKEN" ]; then
  echo "::error::publish: true needs a crates.io credential — run rust-lang/crates-io-auth-action before this step (Trusted Publishing, no stored secret), or set registry-token"
  exit 1
fi

# --- already published? -------------------------------------------------------
# crates.io rejects a duplicate anyway; failing here says so in one line
# instead of a mid-upload error, and makes a re-run's intent explicit.
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "User-Agent: rust-ci cargo-publish" \
  "https://crates.io/api/v1/crates/${NAME}/${VERSION}" || echo "000")
if [ "$CODE" = "200" ]; then
  if [ "${INPUT_ALLOW_ALREADY_PUBLISHED:-false}" = "true" ]; then
    echo "::notice::${NAME} ${VERSION} is already on crates.io; skipping"
    write_outputs false "$VERSION" true
    exit 0
  fi
  echo "::error::${NAME} ${VERSION} is already on crates.io — bump the version, or set allow-already-published for an idempotent re-run"
  exit 1
elif [ "$CODE" = "404" ]; then
  echo "✓ ${NAME} ${VERSION} is not yet on crates.io"
else
  echo "::warning::crates.io check inconclusive (HTTP ${CODE}); continuing — the registry rejects a duplicate regardless"
fi

# --- the upload ---------------------------------------------------------------
# The token reaches cargo through this one call's environment and is never
# written to disk (no `cargo login`, no credentials file).
echo "::group::cargo publish"
CARGO_REGISTRY_TOKEN="$TOKEN" cargo publish "${args[@]}"
echo "::endgroup::"
echo "✓ published ${NAME} ${VERSION} to crates.io"
write_outputs true "$VERSION" false
