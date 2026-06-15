#!/usr/bin/env bash
# Release-readiness checks, run inside the container (networked). Same logic as
# the runner-based action, with --locked added (the workdir is read-only).
# Inputs arrive as env vars; cargo runs in the mounted workdir.
#   INPUT_PACKAGE           package name (required for a multi-member workspace)
#   INPUT_EXPECTED_VERSION  version the crate must declare (else derived from a v* tag)
#   INPUT_RUN_TESTS         "true" to also run cargo test --workspace
set -euo pipefail

# --- select the package from cargo metadata ----------------------------------
META=$(cargo metadata --no-deps --format-version 1)
SUMMARY=$(printf '%s' "$META" | jq -r --arg name "$INPUT_PACKAGE" '
  (if $name == "" then
     (if (.packages | length) == 1 then .packages[0]
      else error("multiple packages; set the package input") end)
   else (.packages[] | select(.name == $name))
   end) as $p
  | ($p.publish == null
     or (($p.publish | type) == "array" and ($p.publish | any(. == "crates-io")))) as $pub
  | "\($p.name)\t\($p.version)\t\($pub)"
')
IFS=$'\t' read -r NAME VERSION PUBLISHABLE <<< "$SUMMARY"
if [ -z "${NAME:-}" ]; then
  echo "::error::package '${INPUT_PACKAGE}' not found in cargo metadata"
  exit 1
fi
echo "crate: $NAME  version: $VERSION  publishable-to-crates.io: $PUBLISHABLE"

# --- tag <-> version coherence -----------------------------------------------
EXPECT="$INPUT_EXPECTED_VERSION"
if [ -z "$EXPECT" ] && [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  EXPECT="${GITHUB_REF#refs/tags/v}"
fi
if [ -n "$EXPECT" ]; then
  if [ "$EXPECT" != "$VERSION" ]; then
    echo "::error::tag/expected version ($EXPECT) != Cargo.toml version ($VERSION)"
    exit 1
  fi
  echo "✓ version matches ($VERSION)"
else
  echo "::notice::no tag or expected-version supplied; skipping coherence check"
fi

# --- publishable vs internal -------------------------------------------------
if [ "$PUBLISHABLE" != "true" ]; then
  echo "::notice::publish = false — internal crate; skipping crates.io checks"
else
  echo "Running cargo publish --dry-run for $NAME"
  if [ -n "$INPUT_PACKAGE" ]; then
    cargo publish --dry-run --locked -p "$NAME"
  else
    cargo publish --dry-run --locked
  fi
  # Not-already-published guard (crates.io API; non-fatal on a network blip).
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "User-Agent: cicd-rust release-readiness" \
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
  cargo test --workspace --locked
fi

echo "✓ release readiness checks passed for $NAME $VERSION"
