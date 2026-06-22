# cicd-rust

Reusable GitHub Actions for Rust CI/CD across our repositories.
Install a toolchain, run the lint-and-test gate, and check a crate's release readiness — without depending on third-party actions whose behaviour drifts with the runner image.

Each action is a composite action under [`.github/actions/`](.github/actions/).
A repository consumes one with `uses: gronke/cicd-rust/.github/actions/<name>@<ref>`.
During bring-up, pin `@main`; once the interface is stable we cut a `v1` tag plus a moving major tag, and consumers pin `@v1`.

## Actions

### `install-toolchain`

Installs Rust via rustup — toolchain, components, and targets — and puts `~/.cargo/bin` on `PATH`.

```yaml
- uses: gronke/cicd-rust/.github/actions/install-toolchain@main
  with:
    toolchain: stable          # or an MSRV like 1.77.2
    components: rustfmt clippy
    targets: ""                # e.g. x86_64-apple-darwin
```

### `lint-and-test`

Runs `cargo fmt --check`, `cargo clippy --all-targets -D warnings`, and `cargo test` for one feature universe.
Call it once per universe for a default / all-features / no-default-features matrix, enabling `fmt` on a single leg so it does not repeat.

```yaml
- uses: gronke/cicd-rust/.github/actions/lint-and-test@main
  with:
    features: ""               # or --all-features / --no-default-features
    fmt: "true"
```

### `check-release-readiness`

Verifies a crate is ready to release.
On a `v*` tag it asserts the tag matches the crate version.
For a publishable crate it runs `cargo publish --dry-run` and checks the version is not already on crates.io.
A crate with `publish = false` is validated for tag/version coherence only, so the action is equally useful for internal crates.

```yaml
- uses: gronke/cicd-rust/.github/actions/check-release-readiness@main
  with:
    package: my-crate          # required only for a workspace with >1 member
    # expected-version: 1.2.3  # defaults to the pushed v* tag
```

## Passing env into the container (Docker actions)

The Docker actions (`cargo-fetch`, `lint-and-test-docker`, `check-release-readiness-docker`) run cargo inside the pinned image, so a variable set on the runner does not reach the build unless the action forwards it.
Each action forwards a configurable set, controlled by three inputs:

- `env-include` — a POSIX-ERE regex matched against variable **names** (anchored full-name); default `CARGO_.*`, so `CARGO_BUILD_JOBS`, `CARGO_NET_RETRY`, `CARGO_TERM_COLOR`, … flow in with no per-variable wiring.
- `env-exclude` — names to drop from the included set; **exclusion wins over inclusion**. Defaults to the action-owned `CARGO_HOME|RUSTUP_HOME|CARGO_TARGET_DIR`.
- `env` — extra literal `KEY=VALUE` lines (one per line) forwarded verbatim, for per-step values (a step-level `env:` on the `uses:` line does not reach a composite action's steps, so this input is how you pass per-invocation values).

Set the variables at the job or workflow level so the action's inner step sees them, then widen the pattern as needed:

```yaml
env:
  CARGO_BUILD_JOBS: "4"
  RUSTFLAGS: "-D warnings"
jobs:
  ci:
    steps:
      - uses: gronke/cicd-rust/.github/actions/lint-and-test-docker@main
        with:
          env-include: "(CARGO_|RUST).*"   # forward cargo + rust vars
          # env-exclude defaults to the owner-vars; add your own to widen the blacklist
          env: |                            # literal extras, always forwarded
            MY_BUILD_FLAG=1
```

Widening `env-include` to `.*` forwards **everything on the runner**, including secrets such as `GITHUB_TOKEN` — prefer a tight `env-include`, or add sensitive names to `env-exclude`.
Regardless of the inputs, the actions always pin `CARGO_HOME`, `RUSTUP_HOME`, and `CARGO_TARGET_DIR` to their in-container paths (after `--env-file`, last-wins), so a forwarded copy can never redirect the mounted cache or target and break the sealed build.

## Self-test

[`.github/workflows/selftest.yml`](.github/workflows/selftest.yml) runs every action against the fixture crate in [`fixtures/sample-crate`](fixtures/sample-crate/) on each push and pull request.
The actions are therefore exercised end-to-end before any consumer relies on them.

## Status and licence

Developed in the `gronke` organisation and consumed there first; it may later move to a public home for broader use across Rust projects.
Released under the MIT licence.
