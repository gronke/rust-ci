# lint-and-test-docker

Run `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings` and `cargo test --workspace` inside the pinned toolchain image, sealed with `--network=none` and `--offline --locked`.
It is the sealed counterpart of `lint-and-test`; run `build-image` and `cargo-fetch` before it, or use the `ci.yml` reusable workflow, which wires the three together.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@v1
- uses: gronke/rust-ci/.github/actions/cargo-fetch@v1
- uses: gronke/rust-ci/.github/actions/lint-and-test-docker@v1
  with:
    features: "--all-features"      # optional; applied to clippy and test
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `image` | `rust-ci:latest` | CI image (Rust toolchain, clippy, rustfmt). |
| `working-directory` | `.` | Crate or workspace directory, mounted read-only. |
| `target-dir` | `target` | Host dir for the cargo target, mounted read-write. Relative to `working-directory`, or absolute. |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME`, mounted read-write; populated by `cargo-fetch`. |
| `features` | `""` | Feature flag applied to clippy and test (e.g. `--all-features`). |
| `offline` | `"true"` | `--network=none` plus `cargo --offline`. `"false"` runs networked and fetches as it builds, with no `cargo-fetch` needed. |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |

## Notes

- The container runs the `lint-and-test` action's own script ([`lint-and-test.sh`](../lint-and-test/lint-and-test.sh)) with `FMT`, `CLIPPY` and `TEST` on, `CLIPPY_ARGS=--all-targets`, `LOCKED=true` and this action's `offline` and `features` inputs; the three commands run in order, the step stops at the first failure, and each has its own log group.
- `--locked` requires a committed `Cargo.lock`; `features` is not applied to `cargo fmt`.
- `RUSTFLAGS` and other non-`CARGO_*` variables do not reach the container unless `env-include` or `env` forwards them; see [docs/sealed-builds.md](../../../docs/sealed-builds.md).
- Runner-side `sccache` and `crates-mirror` configuration is not visible inside the container.
