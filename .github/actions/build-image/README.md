# build-image

Build the rust-ci toolchain image locally from [`image/Dockerfile`](../../../image/Dockerfile) and load it into the Docker daemon, so the Docker actions run against a local tag with no registry pull.

## How it works

The image is `rust:<rust-version>` plus clippy, rustfmt, and jq — plus any cross-compile `targets` you request, so the sealed Docker actions can `cargo check --target <triple>` against them (e.g. `wasm32-unknown-unknown`).
`build-image` builds it for the requested Rust version and `--load`s it into the daemon under `tag`; the Docker actions (`cargo-fetch`, `lint-and-test-docker`, `cargo-docker`, `cargo-use`, `cargo-install`, `publish-dry-run`) then `docker run` that tag — point their `image:` input at it, or use the matching default.

With `cache: "true"` the build runs under buildx with the GitHub Actions cache (`type=gha,mode=min`): only the added layer (clippy/rustfmt/jq) is cached, scoped per Rust version, while the `rust:<version>` base is pulled from Docker Hub.
Caching is off by default, so a consumer opts in before anything writes to their Actions cache.

Pass `rust-version: msrv` to build at the crate's **declared MSRV** instead of a literal tag: the version is read from `Cargo.toml` (`rust-version`) under `working-directory` and validated as numeric, so the whole sealed Docker pipeline can run on the support floor and a dependency that raises its MSRV fails the normal lint-and-test gate rather than the release.
The cache is scoped per *resolved* version (`rust-ci-<version>`), so a latest image and an MSRV image cache independently.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@main
  with:
    rust-version: "1"          # any rust:<tag>; default "latest"
    tag: rust-ci:latest        # the Docker actions' default image
    cache: "true"              # opt in to caching the added layer
    # targets: wasm32-unknown-unknown   # cross targets to add to the image
    # rust-version: msrv       # or build at the crate's declared MSRV (Cargo.toml)
    # working-directory: .     # where that Cargo.toml lives (for rust-version: msrv)
- uses: gronke/rust-ci/.github/actions/lint-and-test-docker@main
  with:
    working-directory: .       # image defaults to rust-ci:latest
```

A sealed cross-target check off that image is then just a `cargo-docker` call:

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-fetch@main
  with:
    working-directory: .
- uses: gronke/rust-ci/.github/actions/cargo-docker@main
  with:
    working-directory: .
    args: "check --workspace --target wasm32-unknown-unknown --locked"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `rust-version` | `latest` | The `rust:<version>` base tag to build on. `msrv` resolves to the crate's declared `rust-version` from `Cargo.toml`. |
| `tag` | `rust-ci:latest` | Tag for the built image. |
| `cache` | `"false"` | Cache the added layer across runs (GitHub Actions cache via buildx `type=gha`). |
| `working-directory` | `.` | Directory whose `Cargo.toml` supplies the version when `rust-version: msrv` (ignored otherwise). |
| `targets` | `""` | Space-separated rustup targets to add to the image (e.g. `wasm32-unknown-unknown`), so the sealed Docker actions can cross-check against them. |

## Outputs

| Output | Description |
| --- | --- |
| `image` | The built image tag. |
