# Rust CI/CD

Reusable GitHub Actions for Rust CI/CD.
Install a toolchain, run the lint-and-test gate, and check a crate's release readiness — without depending on third-party actions whose behaviour drifts with the runner image.

Each action is a composite action under [`.github/actions/`](.github/actions/).
A repository consumes one with `uses: gronke/cicd-rust/.github/actions/<name>@<ref>`.
During bring-up, pin `@main`; once the interface is stable we cut a `v1` tag plus a moving major tag, and consumers pin `@v1`.

## Actions

### `install-toolchain`

Installs Rust via rustup — toolchain, components, and targets — and puts `~/.cargo/bin` on `PATH`.
Works on Linux, macOS and Windows; when a runner ships no Rust at all (e.g. `windows-11-arm`) it bootstraps the arch-appropriate `rustup-init` instead of failing.

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

### `rust-cache`

Caches cargo for CI and **defaults** incremental compilation off — pure cost in CI (no edit→recompile loop), and the main thing that balloons `target/`.
An explicit `CARGO_INCREMENTAL` (set at the workflow/job level) is obeyed — for the occasional variant build that is faster with it on — and flows through to the Docker actions via their `CARGO_.*` forwarding. The action imposes no build profile; set `CARGO_*` vars to tune the build.
Caches the cargo download cache (registry index + `.crate` tarballs + git db) via the first-party `actions/cache`; optionally caches `target/` too, kept bounded by the `Cargo.lock` key (no restore-key ratchet).
Place it before your build/test steps.

```yaml
- uses: gronke/cicd-rust/.github/actions/rust-cache@main
  with:
    prefix: build            # cache family — use a distinct one per job
    cache-target: "true"     # also cache target/ (off by default)
```

### `cargo-docker`

Runs one cargo command inside the pinned image, **sealed**: non-root, all Linux capabilities dropped (`--cap-drop=ALL`), no privilege escalation (`--security-opt=no-new-privileges`), the repo mounted read-only, and — by default — `--network=none` with `cargo --offline` (run `cargo-fetch` first to warm the cache).
The low-level primitive for a network-isolated build: dependency `build.rs` and proc-macros execute during compilation, and with no network they can't exfiltrate or fetch a payload.

```yaml
- uses: gronke/cicd-rust/.github/actions/cargo-fetch@main      # warm the cache (the one networked step)
- uses: gronke/cicd-rust/.github/actions/cargo-docker@main      # sealed build — offline, --network none
  with:
    args: "build --release --locked --features full"  # do NOT add --offline; `offline` controls it
    # offline: "false"   # opt out to fetch-as-it-builds (networked)
```

### `cargo-install`

Install a cargo-based CLI tool into a shared, hardened cargo cache so later sealed runs can use it.
See [the action's README](.github/actions/cargo-install/README.md) for the security model, inputs, and examples.

### `cargo-use`

Run a `cargo-install`'d tool from the shared cache, sealed and network-isolated by default.
See [the action's README](.github/actions/cargo-use/README.md).

### `publish-dry-run`

A release gate split into **network-with-no-code** then **code-with-no-network**.
A networked prep does the publish checks *without building* — cache warm-up, tag ↔ `Cargo.toml` version, a not-already-published probe, and `cargo publish --dry-run --no-verify` — so no dependency code runs while it has the network.
Then the **verify-build runs sealed**: `cargo package --offline` under `--network=none`, so the dependency `build.rs` / proc-macros it compiles and executes can't reach the network. (`cargo publish --dry-run` can't run here — it always contacts the registry, which `--offline` rejects.)

```yaml
- uses: gronke/cicd-rust/.github/actions/publish-dry-run@main
  with:
    package: my-crate          # required only for a workspace with >1 publishable member
    # expected-version: 1.2.3  # defaults to the pushed v* tag
    # git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}   # only for private git deps
```

The runner-based `check-release-readiness` above runs the same checks without Docker (networked, on the runner) for repositories not using the sealed flow.

## Passing env into the container (Docker actions)

The Docker actions (`cargo-fetch`, `cargo-docker`, `cargo-install`, `cargo-use`, `lint-and-test-docker`, `publish-dry-run`) run cargo inside the pinned image, so a variable set on the runner does not reach the build unless the action forwards it.
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

## Private git dependencies (cargo-fetch)

A `Cargo.toml` git dependency on a **private** repository can't be cloned anonymously, and `cargo-fetch` runs cargo inside the container, so the credential has to reach the container's git — not the runner's.
Pass a token through the `git-token` input.
When it is set, `cargo-fetch` configures git to authenticate `github.com` fetches as `x-access-token` and forces cargo to fetch via the git CLI (so the rewrite applies); when it is empty the step is unchanged, so public-only workspaces need nothing.

```yaml
- name: Cargo fetch
  uses: gronke/cicd-rust/.github/actions/cargo-fetch@main
  with:
    git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}
```

The token must carry `contents: read` on every private dependency repository.
The default `GITHUB_TOKEN` only grants access to the workflow's own repository, so a cross-repository dependency needs a fine-grained PAT or a GitHub App installation token, stored as a secret.
See [docs/private-git-dependencies.md](docs/private-git-dependencies.md) for the GitHub App setup and an in-workflow minting example.
The sealed `lint-and-test-docker` passes run `--offline` against the cache `cargo-fetch` populated, so they need no token.

## Self-test

[`.github/workflows/selftest.yml`](.github/workflows/selftest.yml) runs every action against the fixture crate in [`fixtures/sample-crate`](fixtures/sample-crate/) on each push and pull request.
The actions are therefore exercised end-to-end before any consumer relies on them.


## Motivation

GitHub Actions have huge potential for supply-chain attacks. Repeating the same setup across repositories was tedious or required using and combining various other third-party actions, none of which is hardened against malicious build.rs scripts in test-dependencies, that potentially receive less attention than the release dependency tree. What purpose does it have to execute both in the same job context? As Archer would say: "That's how you get ants". Given how quick Rust build caches can grow and how time-consuming it can be to pass artifcats between jobs, Docker is available in GitHub Actions and provides easier means of compartmentalization.
The Docker actions take that further: a build runs sealed — non-root, all capabilities dropped, no privilege escalation, and `--network=none` against a cache a separate `cargo-fetch` warmed — so a dependency `build.rs` or proc-macro compiles but cannot reach the network. `cargo-fetch` is the one networked step; `publish-dry-run` keeps that same seal around the verify-build (`cargo package`), where dependency code is otherwise executed during a release — while the publish checks, which run no build, keep the network.

## Status and licence

Reusable across Rust projects; released under the MIT licence (see [LICENSE](LICENSE)).
