#!/usr/bin/env bash
# Build image/Dockerfile and load the result into the Docker daemon. Inputs arrive
# as env vars from action.yml:
#   RUST_VERSION  the rust:<version> base tag
#   TAG           tag for the built image
#   CACHE         "true" → buildx with the GitHub Actions cache (type=gha,mode=min)
#   SCOPE         gha cache scope (per Rust version)
set -euo pipefail

context="$GITHUB_ACTION_PATH/../../../image"

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
