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

# tag <-> version coherence: a crate-prefixed tag (<package>-vX.Y.Z) names the
# package it releases in a multi-crate workspace; the bare v* form stays for
# single-crate repos and legacy flagship tags.
EXPECT="${INPUT_EXPECTED_VERSION:-}"
if [ -z "$EXPECT" ] && [[ "${GITHUB_REF:-}" == "refs/tags/${NAME}-v"* ]]; then
  EXPECT="${GITHUB_REF#refs/tags/"${NAME}"-v}"
fi
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

# Optional ordering gate for multi-crate workspaces: every workspace path
# dependency of the selected package must already be live on crates.io at the
# version the manifest requires, because publishing strips the path and the
# registry copy is what consumers (and the sealed verify-build) resolve.
# The probe names the fix; the resolution during packaging below still gates
# even when the probe is inconclusive.
if [ "${INPUT_REQUIRE_DEPS_PUBLISHED:-false}" = "true" ] && [ "$PUBLISHABLE" = "true" ]; then
  echo "::group::dependency liveness (workspace path deps on crates.io)"
  DEPS=$(printf '%s' "$META" | jq -r --arg name "$NAME" '
    .packages[] | select(.name == $name) | .dependencies[]
    | select(.path != null) | "\(.name)\t\(.req)"')
  while IFS=$'\t' read -r dep req; do
    [ -z "$dep" ] && continue
    # The house pin shape is an exact minimum ("^X.Y.Z"); probe that version.
    ver="${req#^}"; ver="${ver#=}"; ver="${ver%%,*}"; ver="${ver// /}"
    CODE=$(curl -s -o /dev/null -w '%{http_code}' \
      -H "User-Agent: rust-ci publish-dry-run" \
      "https://crates.io/api/v1/crates/${dep}/${ver}" || echo "000")
    if [ "$CODE" = "200" ]; then
      echo "✓ ${dep} ${ver} is on crates.io"
    elif [ "$CODE" = "404" ]; then
      echo "::error::${dep} ${ver} is not on crates.io; release ${dep} first, then re-tag ${NAME}"
      exit 1
    else
      echo "::warning::crates.io check for ${dep} ${ver} inconclusive (HTTP ${CODE}); the packaging resolution below still gates"
    fi
  done <<< "$DEPS"
  echo "::endgroup::"
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

  # Build the .crate itself (still no build of dependency code): it is the
  # artifact a caller may upload, and its packaged Cargo.lock names exactly
  # what the sealed verify-build must resolve. The workspace fetch above
  # resolves path members from the tree, so a co-developed dependency's
  # REGISTRY copy is never in the cache; fetching against the packaged
  # manifest warms it for --offline resolution.
  echo "::group::cargo package --no-verify (build the .crate)"
  cargo package --no-verify --locked -p "$NAME"
  echo "::endgroup::"
  crate_file="${CARGO_TARGET_DIR:-target}/package/${NAME}-${VERSION}.crate"
  warm="${CARGO_TARGET_DIR:-target}/.cicd-publish-warm"
  rm -rf "$warm" && mkdir -p "$warm"
  tar -xzf "$crate_file" -C "$warm"
  # The scratch copy lives under the workspace's target dir, so cargo would
  # walk up and refuse ("believes it's in a workspace"); an empty [workspace]
  # table makes it standalone. Scratch only; the .crate itself is untouched.
  printf '\n[workspace]\n' >> "$warm/${NAME}-${VERSION}/Cargo.toml"
  echo "::group::cargo fetch (packaged manifest: registry copies of path deps)"
  cargo fetch --locked --manifest-path "$warm/${NAME}-${VERSION}/Cargo.toml"
  echo "::endgroup::"
fi

# Hand the resolved package to the sealed verify step (target is mounted RW + shared).
out="${CARGO_TARGET_DIR:-target}/.cicd-publish-dry-run"
mkdir -p "$(dirname "$out")"
printf '%s\t%s\n' "$NAME" "$PUBLISHABLE" > "$out"
