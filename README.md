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

## Self-test

[`.github/workflows/selftest.yml`](.github/workflows/selftest.yml) runs every action against the fixture crate in [`fixtures/sample-crate`](fixtures/sample-crate/) on each push and pull request.
The actions are therefore exercised end-to-end before any consumer relies on them.

## Status and licence

Developed in the `gronke` organisation and consumed there first; it may later move to a public home for broader use across Rust projects.
Released under the MIT licence.
