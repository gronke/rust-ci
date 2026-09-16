# Sealed builds

The Docker actions (`cargo-fetch`, `cargo-docker`, `lint-and-test-docker`, `publish-dry-run`, `cargo-install`, `cargo-use`) run cargo inside the toolchain image that `build-image` loads into the local Docker daemon; `msrv` runs inside the plain `rust:<msrv>` image, which it pulls itself.
Every container starts through one shared `docker run` in [`.github/actions/_lib/seal.sh`](../.github/actions/_lib/seal.sh); this page lists what that run does and what follows from it.

## The seal

- `--user "$(id -u):$(id -g)"`: cargo runs as the runner's user, not root, with `HOME=/tmp`.
- `--cap-drop=ALL` and `--security-opt=no-new-privileges`.
- `working-directory` is mounted read-only at `/work`, unconditionally; no input makes that mount writable.
- `--network=none` when the action runs offline; the cargo steps also pass `--offline`, so a `build.rs` or proc-macro that executes during compilation has no route to the network and no crate is downloaded mid-build.
- `cargo-cache` is mounted read-write at `/cache/cargo`; `target-dir`, when set, is mounted read-write at `/work/target`.
- `CARGO_HOME=/cache/cargo`, `RUSTUP_HOME=/usr/local/rustup` and, with a `target-dir`, `CARGO_TARGET_DIR=/work/target` are the container's values; no input changes them (see Forwarding environment).

The one exception to the read-only mount is the `msrv` action's `cargo generate-lockfile`, which runs with a read-write mount of a disposable copy of the source under `RUNNER_TEMP`, never of the checkout.

## One networked step

`cargo-fetch` runs `cargo fetch --locked` with the network on (every other part of the seal still applies) and fills `cargo-cache`.
The sealed actions then resolve from that cache; a crate missing from it fails the build instead of triggering a download, so `cargo-fetch` must see the same `working-directory` and `cargo-cache` as the steps after it.
`offline` defaults to `"true"` on `cargo-docker`, `lint-and-test-docker` and `cargo-use`, and to `"false"` on `msrv`; `cargo-install` is always networked, and `publish-dry-run` runs its own networked prep before its sealed verify-build.

## Forwarding environment

A variable set on the runner reaches the container only through three inputs, present on every Docker action:

- `env-include`: POSIX ERE matched against the whole variable name; default `CARGO_.*`, so `CARGO_BUILD_JOBS`, `CARGO_NET_RETRY` or `CARGO_TERM_COLOR` flow in with no per-variable wiring.
- `env-exclude`: names dropped from the included set (exclusion wins); default empty.
- `env`: lines for docker's `--env-file`, one per line, forwarded regardless of the two patterns: a `KEY=VALUE` line is passed verbatim, and a bare `NAME` line forwards that variable from the runner environment when it is set there (an unset name stays unset in the container), so a job that exports `GITHUB_TOKEN` as a variable forwards it with one line.

`CARGO_HOME` and `RUSTUP_HOME` are always pinned to `/cache/cargo` and `/usr/local/rustup`, and `CARGO_TARGET_DIR` to `/work/target` whenever a `target-dir` is mounted, with `-e` flags; `-e` overrides `--env-file`, so a forwarded copy of a pinned name is ignored and none of the three needs an `env-exclude` entry.
Without a `target-dir` the container has no writable target mount, so a forwarded `CARGO_TARGET_DIR` can redirect nothing on the host.

`env-include` filters the environment of the runner process that runs the action (`env | awk` in `seal.sh`); `env` adds lines for one invocation.

```yaml
env:
  CARGO_BUILD_JOBS: "4"
  RUSTFLAGS: "-D warnings"
jobs:
  ci:
    steps:
      - uses: gronke/rust-ci/.github/actions/lint-and-test-docker@v1
        with:
          env-include: "(CARGO_|RUST).*"   # forward cargo and rust vars
          env: |                            # literal extras, always forwarded
            MY_BUILD_FLAG=1
```

`env-include: ".*"` forwards everything in the runner's environment, including `GITHUB_TOKEN` and any secret the job exposes as a variable.
Keep the include tight, or add sensitive names to `env-exclude`.

## Paths

- Only `working-directory` is mounted, so a path dependency outside it does not exist inside the container; keep path dependencies below `working-directory`, or point `working-directory` at the workspace root.
- `target-dir` and `cargo-cache` are relative to `working-directory` unless absolute; `${{ runner.temp }}/target`, or the `CARGO_TARGET_DIR` that `rust-cache`'s `local-target` exports, are valid values.
- `publish-dry-run` fails when the `.crate` would package a cargo build tree or cargo home; keep `target-dir` and `cargo-cache` outside the crate directory or exclude them in `Cargo.toml`.
- `cargo-docker` translates a build script's `OUT_DIR` from `/work/target/...` back to the host side of `target-dir`; nothing outside the target mount is writable, so nothing else can be a build output.

## Not in the container

- `sccache` installs its binary under `RUNNER_TEMP` and exports `RUSTC_WRAPPER` on the runner; neither is in the container, and the default include does not match `RUSTC_WRAPPER`, so the sealed actions compile without it.
  Forwarding it (for example with `env-include: "RUST.*"`) points cargo at a wrapper path that does not exist in the container.
- `crates-mirror` writes the source replacement into the runner's `$CARGO_HOME/config.toml`; the container's `CARGO_HOME` is `cargo-cache`, so the replacement does not apply and offline resolution uses the crates.io cache that `cargo-fetch` filled.

## Private git dependencies

`cargo-fetch` and `publish-dry-run` take a `git-token`, with `git-host`, `git-username` and `git-path`, and hand it to the container as `GIT_CONFIG_*` env-file lines plus `CARGO_NET_GIT_FETCH_WITH_CLI=true`; `route-git-token` exports the same entries through `GITHUB_ENV` for steps on the runner, and both build them with `.github/actions/_lib/git-route.sh`.
How to obtain a token that can read the dependency repositories: [private-git-dependencies.md](private-git-dependencies.md).
