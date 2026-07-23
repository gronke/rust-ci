#!/usr/bin/env bash
# Verify a cargo crate is ready to release. Inputs arrive as env vars from
# action.yml; cargo runs in the step's working-directory.
#   INPUT_PACKAGE           package name (required for a multi-member workspace)
#   INPUT_VERSION           the declared version (skips cargo; for non-crate repositories)
#   INPUT_CHANGELOG         changelog path for the no-crate fallback (default CHANGELOG.md)
#   INPUT_EXPECTED_VERSION  version the crate must declare (else derived from a v* tag)
#   INPUT_RUN_TESTS         "true" to also run cargo test --workspace
set -euo pipefail

# --- the declared version -----------------------------------------------------
# The ladder: the explicit input, else Cargo.toml, else the changelog's newest
# released section — the manifest equivalent of a repository without a crate.
source "$GITHUB_ACTION_PATH/../_lib/crate-version.sh"
source "$GITHUB_ACTION_PATH/../_lib/changelog-version.sh"
NAME="" VERSION="" PUBLISHABLE="false"
if [ -n "${INPUT_VERSION:-}" ]; then
  VERSION="$INPUT_VERSION"
  echo "declared version (input): $VERSION"
elif [ -f Cargo.toml ]; then
  resolve_crate "$INPUT_PACKAGE"
  NAME="$CRATE_NAME" VERSION="$CRATE_VERSION" PUBLISHABLE="$CRATE_PUBLISHABLE"
  echo "crate: $NAME  version: $VERSION  publishable-to-crates.io: $PUBLISHABLE"
else
  resolve_changelog_version "${INPUT_CHANGELOG:-CHANGELOG.md}"
  VERSION="$CHANGELOG_LATEST"
  if [ -z "$VERSION" ]; then
    echo "::error::no Cargo.toml, no version input, and no released changelog section — nothing declares a version"
    exit 1
  fi
  echo "declared version (the changelog's newest released section): $VERSION"
fi

# --- tag <-> version coherence -----------------------------------------------
EXPECT="$INPUT_EXPECTED_VERSION"
if [ -z "$EXPECT" ] && [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  EXPECT="${GITHUB_REF#refs/tags/v}"
fi
if [ -n "$EXPECT" ]; then
  if [ "$EXPECT" != "$VERSION" ]; then
    echo "::error::tag/expected version ($EXPECT) != declared version ($VERSION)"
    exit 1
  fi
  echo "✓ version matches ($VERSION)"
else
  echo "::notice::no tag or expected-version supplied; skipping coherence check"
fi

# --- publishable vs internal -------------------------------------------------
if [ "$PUBLISHABLE" != "true" ]; then
  echo "::notice::not publishable to crates.io (publish = false, or no crate); skipping crates.io checks"
else
  echo "Running cargo publish --dry-run for $NAME"
  if [ -n "$INPUT_PACKAGE" ]; then
    cargo publish --dry-run -p "$NAME"
  else
    cargo publish --dry-run
  fi
  # Not-already-published guard (crates.io API; non-fatal on a network blip).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "User-Agent: rust-ci release-readiness" \
    "https://crates.io/api/v1/crates/${NAME}/${VERSION}" || echo "000")
  if [ "$CODE" = "200" ]; then
    echo "::error::${NAME} ${VERSION} is already published on crates.io"
    exit 1
  elif [ "$CODE" = "404" ]; then
    echo "✓ ${NAME} ${VERSION} is not yet on crates.io"
  else
    echo "::warning::crates.io check inconclusive (HTTP ${CODE}); skipping"
  fi
fi

# --- optional test pass ------------------------------------------------------
if [ "$INPUT_RUN_TESTS" = "true" ]; then
  if [ -f Cargo.toml ]; then
    cargo test --workspace
  else
    echo "::notice::run-tests requested but there is no Cargo.toml; skipping"
  fi
fi

echo "✓ release readiness checks passed for ${NAME:+$NAME }$VERSION"
