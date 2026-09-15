# build-image

Build the rust-ci toolchain image from [`image/Dockerfile`](../../../image/Dockerfile) and load it into the Docker daemon, so the Docker actions run against a local tag; the built image is not pushed to a registry.
Run it once before `cargo-fetch`, `lint-and-test-docker`, `cargo-docker`, `cargo-install`, `cargo-use` and `publish-dry-run`; point their `image` input at `tag`, or keep the shared default `rust-ci:latest`.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@v1
  with:
    rust-version: "1"          # any rust:<tag>; default "latest"
    tag: rust-ci:latest        # the Docker actions' default image
    cache: "true"              # cache the added layer in the Actions cache
    # targets: wasm32-unknown-unknown   # cross targets baked into the image
    # rust-version: msrv       # build at the crate's declared MSRV (Cargo.toml)
    # working-directory: .     # where that Cargo.toml lives (for rust-version: msrv)
- uses: gronke/rust-ci/.github/actions/lint-and-test-docker@v1
  with:
    working-directory: .       # image defaults to rust-ci:latest
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `rust-version` | `latest` | The `rust:<version>` base tag to build on. `msrv` resolves to the crate's declared `rust-version` from `Cargo.toml` under `working-directory`. |
| `tag` | `rust-ci:latest` | Tag for the built image. |
| `cache` | `"false"` | Cache the added layer across runs (GitHub Actions cache via buildx `type=gha`). |
| `working-directory` | `.` | Directory whose `Cargo.toml` supplies the version when `rust-version: msrv` (ignored otherwise). |
| `targets` | `""` | Space-separated rustup targets to add to the image (e.g. `wasm32-unknown-unknown`). Empty adds none. |

## Outputs

| Output | Description |
| --- | --- |
| `image` | The built image tag. |

## Notes

- The image is `rust:<rust-version>` plus clippy, rustfmt, jq and any `targets`; a sealed `cargo-docker` step can then run `check --target <triple>` against it.
- `cache: "true"` builds under buildx with `type=gha,mode=min`: only the added layer is cached, scoped per resolved Rust version (`rust-ci-<version>`), and the `rust:<version>` base is pulled from Docker Hub, not from the Actions cache.
- `cache: "true"` also exports the masked `ACTIONS_RUNTIME_TOKEN` and `ACTIONS_RESULTS_URL` into the job environment, because buildx needs them for the cache; a cache error is ignored and the image still loads.
- `rust-version: msrv` accepts only a numeric `major[.minor[.patch]]` from `Cargo.toml`; any other `rust-version` value is passed through as the base tag.
- The build retries on transient registry output (timeouts, resets, rate limits) and fails at once on a genuine build error.
