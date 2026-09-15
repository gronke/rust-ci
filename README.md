# rust-ci

Composite GitHub Actions for Rust projects: toolchain and QA gates, sealed Docker builds, cargo and sccache caching, a Keep a Changelog release flow, and crates.io publishing.
Each action lives under `.github/actions/<name>` and is consumed with `uses: gronke/rust-ci/.github/actions/<name>@v1`.
The sealed actions run dependency code with no network, so a build script or proc-macro cannot reach out during a build.
Every action has its own README with inputs, outputs and an example; this page is the map.

## Quick start

A native job: toolchain, cache, lint and test, cache save.

```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: gronke/rust-ci/.github/actions/install-toolchain@v1
        with:
          components: rustfmt clippy
      - uses: gronke/rust-ci/.github/actions/rust-cache@v1
        with:
          cache-target: "true"
      - uses: gronke/rust-ci/.github/actions/lint-and-test@v1
      - uses: gronke/rust-ci/.github/actions/rust-cache-save@v1
        if: always()
        with:
          save: ${{ github.ref == 'refs/heads/main' }}
```

The sealed pipeline as one reusable-workflow call: build the toolchain image, warm the cache once, then fmt, clippy and test with `--network=none`, plus optional cross-target and MSRV checks.

```yaml
jobs:
  ci:
    uses: gronke/rust-ci/.github/workflows/ci.yml@v1
    with:
      targets: wasm32-unknown-unknown   # optional: sealed cross-checks
```

| Input | Default | Description |
| --- | --- | --- |
| `rust-version` | `latest` | `rust:<tag>` base for the image, or `msrv`. |
| `targets` | `""` | Space-separated rustup targets to cross-check. |
| `features` | `""` | Feature flag for the sealed lint-and-test leg. |
| `msrv` | `true` | Also verify the crate on its declared MSRV. |
| `working-directory` | `.` | Crate directory. |

## Actions

Each name links to the action's README.

### Toolchain and QA

| Action | Does |
| --- | --- |
| [`install-toolchain`](.github/actions/install-toolchain/README.md) | Install a rustup toolchain with components and targets and put cargo on `PATH`. |
| [`lint-and-test`](.github/actions/lint-and-test/README.md) | Run `cargo fmt --check`, `cargo clippy -D warnings` and `cargo test` for one feature set. |
| [`msrv`](.github/actions/msrv/README.md) | Compile the crate on its declared `rust-version` inside a container built at that toolchain. |
| [`cargo-out-dir`](.github/actions/cargo-out-dir/README.md) | Build a package and expose its build script's `OUT_DIR`. |

### Sealed Docker builds

| Action | Does |
| --- | --- |
| [`build-image`](.github/actions/build-image/README.md) | Build the `rust:<version>` toolchain image locally, with no registry. |
| [`cargo-fetch`](.github/actions/cargo-fetch/README.md) | Warm the cargo cache, the one networked step. |
| [`cargo-docker`](.github/actions/cargo-docker/README.md) | Run one cargo command sealed: non-root, no capabilities, read-only source, no network. |
| [`lint-and-test-docker`](.github/actions/lint-and-test-docker/README.md) | The lint-and-test gate, sealed. |
| [`cargo-install`](.github/actions/cargo-install/README.md) | Install a cargo tool into the shared cargo cache, sealed. |
| [`cargo-use`](.github/actions/cargo-use/README.md) | Run an installed tool from that cache, sealed. |
| [`publish-dry-run`](.github/actions/publish-dry-run/README.md) | Publish checks without a build, then the verify-build sealed. |
| [`route-git-token`](.github/actions/route-git-token/README.md) | Route git fetches on the runner through a short-lived token, for jobs outside the container. |

### Caching

| Action | Does |
| --- | --- |
| [`rust-cache`](.github/actions/rust-cache/README.md) | Restore cargo's registry cache and, optionally, `target/`. |
| [`rust-cache-save`](.github/actions/rust-cache-save/README.md) | Prune `target/` to dependency artifacts and save it, as the job's last step. |
| [`sccache`](.github/actions/sccache/README.md) | Install a pinned sccache as `RUSTC_WRAPPER`; the backend comes from `SCCACHE_*` in the job environment. |
| [`sccache-stats`](.github/actions/sccache-stats/README.md) | Record sccache's hits and misses for the timing report. |
| [`crates-mirror`](.github/actions/crates-mirror/README.md) | Point cargo's crates-io source at a mirror URL. |

### Release

| Action | Does |
| --- | --- |
| [`changelog`](.github/actions/changelog/README.md) | Check, cut or render a Keep a Changelog file against the crate version. |
| [`check-release-readiness`](.github/actions/check-release-readiness/README.md) | Assert tag and version coherence and that the version is not yet on crates.io. |
| [`cut-release`](.github/actions/cut-release/README.md) | Start a release: changelog cut, release branch, merge-back pull request, pipeline dispatch. |
| [`draft-release`](.github/actions/draft-release/README.md) | Create or refresh the draft pre-release and push the next candidate marker. |
| [`release-guidance`](.github/actions/release-guidance/README.md) | Write the release manager's next steps into the step summary. |
| [`promote-release`](.github/actions/promote-release/README.md) | Promote a candidate from the pipeline, or defer to a human signature. |
| [`require-signed-tag`](.github/actions/require-signed-tag/README.md) | Gate a pipeline on a verified signed annotated tag. |
| [`publish-draft-release`](.github/actions/publish-draft-release/README.md) | Seal the final tag against the newest marker, publish the draft, move the major tag. |

### Publish

| Action | Does |
| --- | --- |
| [`require-signed-release`](.github/actions/require-signed-release/README.md) | Answer whether a verified human signature covers the release commit. |
| [`cargo-publish`](.github/actions/cargo-publish/README.md) | Publish the crate to crates.io, or rehearse it. |

### Observability

| Action | Does |
| --- | --- |
| [`timing-start`](.github/actions/timing-start/README.md), [`timing-mark`](.github/actions/timing-mark/README.md), [`timing-report`](.github/actions/timing-report/README.md) | Per-stage durations, CPU and memory for one job, rendered into the step summary. |

## Self-hosted runners

An sccache backend, a crates mirror and a persistent target directory reach the actions as job-environment variables, which a host provides through the runner's job-started hook.
[docs/self-hosted.md](docs/self-hosted.md) lists the variables, the hook and the trust notes.

## Guides

- [docs/showcase.md](docs/showcase.md): QA, test, release and publish end to end, and the hardened variant.
- [docs/sealed-builds.md](docs/sealed-builds.md): the seal model and how environment reaches the container.
- [docs/release-flow.md](docs/release-flow.md): the release runbook, candidate loop and go-live modes.
- [docs/self-hosted.md](docs/self-hosted.md): host-provided services.
- [docs/private-git-dependencies.md](docs/private-git-dependencies.md): tokens for private git dependencies.
- [docs/cache-operations.md](docs/cache-operations.md): inspecting and trimming the repository cache.

## Versioning

Pin `@v1`, the moving major, or an exact release tag.
`CHANGELOG.md` follows Keep a Changelog, and releases are cut with this repository's own actions.

## Self-test

[`.github/workflows/selftest.yml`](.github/workflows/selftest.yml) exercises every action against [`fixtures/sample-crate`](fixtures/sample-crate/) on each pull request.
`scripts/lint.sh` runs shellcheck, yamllint, actionlint (through Docker) and the em-dash check locally.

## Licence

MIT, see [LICENSE](LICENSE).
