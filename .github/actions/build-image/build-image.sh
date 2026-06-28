#!/usr/bin/env bash
# Build image/Dockerfile and load the result into the Docker daemon. Inputs arrive
# as env vars from action.yml:
#   RUST_VERSION       the rust:<version> base tag; the literal `msrv` is resolved to
#                      the declared rust-version from WORKING_DIRECTORY/Cargo.toml
#   WORKING_DIRECTORY  crate dir read for the `msrv` sentinel (default ".")
#   TAG                tag for the built image
#   CACHE              "true" → buildx with the GitHub Actions cache (type=gha,mode=min)
# The buildx cache scope is derived per resolved Rust version (rust-ci-<version>).
set -euo pipefail

# Resolve the `msrv` sentinel to the crate's declared rust-version (validated: numeric
# only, so a crafted manifest can't smuggle a docker tag). Any other value is a literal
# base tag (latest, 1, 1.95, bookworm, …) and is used as-is.
if [ "${RUST_VERSION:-}" = "msrv" ]; then
  # shellcheck source=/dev/null
  source "$GITHUB_ACTION_PATH/../_lib/rust-version.sh"
  resolve_msrv_from_cargo "${WORKING_DIRECTORY:-.}" || exit 1
  RUST_VERSION="$RESOLVED_MSRV"
  echo "Resolved MSRV from ${WORKING_DIRECTORY:-.}/Cargo.toml: rust:$RUST_VERSION"
fi

context="$GITHUB_ACTION_PATH/../../../image"
SCOPE="rust-ci-$RUST_VERSION"

if [ "${CACHE:-false}" = "true" ]; then
  echo "::group::buildx build (gha cache)"
  # type=gha caches only the added layer (mode=min); the rust base is pulled from
  # Docker Hub. A docker-container builder is required; pin a buildkit that speaks
  # the v2 Actions cache service. ignore-error keeps a cache hiccup from failing
  # the build (the image still loads).
  docker buildx inspect rust-ci-builder >/dev/null 2>&1 \
    || docker buildx create --name rust-ci-builder --driver docker-container \
         --driver-opt image=moby/buildkit:latest >/dev/null
  docker buildx build --builder rust-ci-builder \
    --build-arg "RUST_VERSION=$RUST_VERSION" \
    --cache-from "type=gha,scope=$SCOPE" \
    --cache-to "type=gha,mode=min,scope=$SCOPE,ignore-error=true" \
    --load -t "$TAG" "$context"
  echo "::endgroup::"
else
  echo "::group::docker build"
  docker build --build-arg "RUST_VERSION=$RUST_VERSION" -t "$TAG" "$context"
  echo "::endgroup::"
fi
