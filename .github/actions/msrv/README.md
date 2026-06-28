# msrv

Compile a crate on its **declared minimum supported Rust version** to catch a dependency that raises its own MSRV — on the PR that pulls it in, not only at release time.

## How it works

The action reads `rust-version` from the crate's `Cargo.toml`, builds the toolchain image at *exactly* that Rust version (`image/Dockerfile` on `rust:<msrv>`), and runs `cargo check` inside it, sealed.
Because the container's compiler **is** the declared MSRV, a plain `cargo check` is the MSRV check — there is no separate MSRV tool to install and no toolchain to select.

**When you need it:** if your main CI already runs the sealed Docker pipeline, set `build-image`'s `rust-version: msrv` instead and the normal `lint-and-test` gate enforces the MSRV across fmt/clippy/test — this action is then redundant. It earns its place when CI runs **natively** or on **stable**: a dedicated, cheap (`cargo check`) floor gate you add as a single job without converting the rest of the pipeline.

The check runs through the same hardened `docker run` as the other Docker actions (non-root, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, repo mounted read-only).
By default it is **networked** (otherwise sealed), so dependencies resolve fresh with no `cargo-fetch` warmup and a newer release within range is caught; set `offline: "true"` (after a `cargo-fetch`) for a `--network none` run.
Resolution is **unlocked** by default (`locked: "false"`) so it reflects what a fresh consumer build would pick, which a committed `Cargo.lock` would otherwise hide.

## Usage

```yaml
# Runs on every PR + push to main — the timing that catches MSRV drift early.
- uses: actions/checkout@v4
- uses: gronke/rust-ci/.github/actions/msrv@main
  with:
    package: my-crate          # required for a workspace with >1 member
    features: "--features full" # optional; the flag passed to cargo check
    # rust-version: "1.95"     # optional override; default reads Cargo.toml
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `package` | `""` | Package to check (`-p`); required for a multi-member workspace. |
| `features` | `""` | Feature flag passed to `cargo check` (e.g. `--features full`). |
| `rust-version` | `""` | MSRV to test. Empty reads `rust-version` from `Cargo.toml`. |
| `working-directory` | `.` | Crate/workspace directory (Cargo.toml read from here; mounted read-only). |
| `locked` | `"false"` | Append `--locked` (test the pinned lockfile instead of fresh resolution). |
| `offline` | `"false"` | Sealed `--network none` + `--offline` (needs a prior `cargo-fetch`). |
| `image-tag` | `rust-ci:msrv` | Local tag for the MSRV image, distinct from `rust-ci:latest`. |
| `target-dir` | `target` | Host dir for cargo target (read-write, cacheable). |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME`. |
| `env-include` / `env-exclude` / `env` | cargo vars | Env forwarding into the container (see `lint-and-test-docker`). |

The declared MSRV must be numeric (`1.95` or `1.95.0`); a non-numeric value is rejected before it can reach a docker tag.
