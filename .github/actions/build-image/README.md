# build-image

Build the rust-ci toolchain image locally from [`image/Dockerfile`](../../../image/Dockerfile) and load it into the Docker daemon, so the Docker actions run against a local tag with no registry pull.

## How it works

The image is `rust:<rust-version>` plus clippy, rustfmt, and jq.
`build-image` builds it for the requested Rust version and `--load`s it into the daemon under `tag`; the Docker actions (`cargo-fetch`, `lint-and-test-docker`, `cargo-docker`, `cargo-use`, `cargo-install`, `publish-dry-run`) then `docker run` that tag — point their `image:` input at it, or use the matching default.

With `cache: "true"` the build runs under buildx with the GitHub Actions cache (`type=gha,mode=min`): only the added layer (clippy/rustfmt/jq) is cached, scoped per Rust version, while the `rust:<version>` base is pulled from Docker Hub.
Caching is off by default, so a consumer opts in before anything writes to their Actions cache.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@main
  with:
    rust-version: "1"          # any rust:<tag>; default "latest"
    tag: rust-ci:latest        # the Docker actions' default image
    cache: "true"              # opt in to caching the added layer
- uses: gronke/rust-ci/.github/actions/lint-and-test-docker@main
  with:
    working-directory: .       # image defaults to rust-ci:latest
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `rust-version` | `latest` | The `rust:<version>` base tag to build on. |
| `tag` | `rust-ci:latest` | Tag for the built image. |
| `cache` | `"false"` | Cache the added layer across runs (GitHub Actions cache via buildx `type=gha`). |

## Outputs

| Output | Description |
| --- | --- |
| `image` | The built image tag. |
