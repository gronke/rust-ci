# msrv

Compile a crate on its declared minimum supported Rust version: the action reads `rust-version` from `Cargo.toml`, builds the toolchain image at exactly that version and runs a sealed `cargo check` inside it.
Use it as the MSRV gate when the main CI runs natively or on stable; a pipeline that already runs the sealed Docker actions can instead pass `rust-version: msrv` to `build-image`, and the normal `lint-and-test-docker` gate then enforces the MSRV.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: gronke/rust-ci/.github/actions/msrv@v1
  with:
    package: my-crate           # required for a workspace with more than one member
    features: "--features full" # optional; the flag passed to cargo check
    # rust-version: "1.95"      # optional override; default reads Cargo.toml
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `package` | `""` | Package to check (`-p`); required for a workspace with more than one member. |
| `features` | `""` | Feature flag passed to `cargo check` (e.g. `--features full`, `--all-features`). |
| `rust-version` | `""` | MSRV to test. Empty reads `rust-version` from the crate's `Cargo.toml`. |
| `working-directory` | `.` | Crate or workspace directory, mounted read-only; `Cargo.toml` is read from here. |
| `locked` | `"false"` | `"false"` resolves a fresh `Cargo.lock` at the MSRV in a disposable copy of the source; `"true"` requires a committed `Cargo.lock` and checks exactly those versions. |
| `offline` | `"false"` | `"true"` runs `--network=none` plus `cargo --offline` and needs a prior `cargo-fetch`. |
| `image-tag` | `rust-ci:msrv` | Local tag for the MSRV image, distinct from `rust-ci:latest`. |
| `target-dir` | `target` | Host dir for the cargo target, mounted read-write. |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME`, mounted read-write. |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `CARGO_HOME\|RUSTUP_HOME\|CARGO_TARGET_DIR` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim. |

## Notes

- The image is the full toolchain image (`image/Dockerfile` on `rust:<msrv>`: clippy, rustfmt, jq), built without the Actions cache under `image-tag` on every run; the check is `cargo check [-p <package>] --locked [<features>]` after `rustc --version`.
- The declared or overridden version must be numeric (`1.95` or `1.95.0`); anything else is rejected before it can become a Docker tag.
- `locked: "false"` copies the source under `RUNNER_TEMP` (skipping the top-level `target-dir`, `cargo-cache` and `.git` entries), materialises a self-contained `.git` there so a `build.rs` that reads `git describe` behaves as in the checkout, symlinks the cache and target dirs in, runs `cargo generate-lockfile` with a read-write mount of that copy, and checks the copy; the checkout is never written.
- By default the check is networked (dependencies resolve fresh, no `cargo-fetch`); the rest of the seal (non-root, `--cap-drop=ALL`, `no-new-privileges`, source read-only) still applies.
- `locked: "true"` with no committed `Cargo.lock` fails before the image is built.
