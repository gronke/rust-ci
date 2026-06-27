#!/usr/bin/env bash
# Networked prep for the publish dry-run (no dependency build runs here):
#   1. warm the cargo cache (cargo fetch) so the sealed verify step can run offline,
#   2. select the package from cargo metadata,
#   3. assert the tag (or expected-version) matches Cargo.toml,
#   4. probe crates.io that the version is not already published.
# Hands the resolved package name + publishability to the sealed verify step via a
# marker file under the mounted (RW, shared) target dir.
# Inputs via env: INPUT_PACKAGE, INPUT_EXPECTED_VERSION, GITHUB_REF, CICD_GIT_TOKEN.
set -euo pipefail

# Private git deps: authenticate github.com as x-access-token and force the git CLI
# so cargo can clone them (no-op for public deps). Same handling as cargo-fetch.
if [ -n "${CICD_GIT_TOKEN:-}" ]; then
  git config --global url."https://x-access-token:${CICD_GIT_TOKEN}@github.com/".insteadOf "https://github.com/"
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
fi

echo "::group::cargo fetch"
cargo fetch --locked
echo "::endgroup::"

# Select the package (--no-deps reads manifests only; no resolution/network).
META=$(cargo metadata --no-deps --format-version 1)
SUMMARY=$(printf '%s' "$META" | jq -r --arg name "${INPUT_PACKAGE:-}" '
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
  echo "::error::package '${INPUT_PACKAGE:-}' not found in cargo metadata"
  exit 1
fi
echo "crate: $NAME  version: $VERSION  publishable-to-crates.io: $PUBLISHABLE"

# tag <-> version coherence
EXPECT="${INPUT_EXPECTED_VERSION:-}"
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

# not-already-published probe (crates.io API; non-fatal on a network blip)
if [ "$PUBLISHABLE" = "true" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "User-Agent: rust-ci publish-dry-run" \
    "https://crates.io/api/v1/crates/${NAME}/${VERSION}" || echo "000")
  if [ "$CODE" = "200" ]; then
    echo "::error::${NAME} ${VERSION} is already published on crates.io"
    exit 1
  elif [ "$CODE" = "404" ]; then
    echo "✓ ${NAME} ${VERSION} is not yet on crates.io"
  else
    echo "::warning::crates.io check inconclusive (HTTP ${CODE}); skipping"
  fi

  # Publish / packaging / metadata checks WITHOUT a build (--no-verify), so no
  # dependency code runs here; the verify-BUILD is done sealed + offline by verify.sh.
  echo "::group::cargo publish --dry-run --no-verify (publish checks, no build)"
  cargo publish --dry-run --no-verify --locked -p "$NAME"
  echo "::endgroup::"
fi

# Hand the resolved package to the sealed verify step (target is mounted RW + shared).
out="${CARGO_TARGET_DIR:-target}/.cicd-publish-dry-run"
mkdir -p "$(dirname "$out")"
printf '%s\t%s\n' "$NAME" "$PUBLISHABLE" > "$out"
