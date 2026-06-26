# cargo-use

Run a tool that [`cargo-install`](../cargo-install/README.md) placed in the shared cargo cache, from a hardened container.

## How it works

By default the tool runs inside the pinned image, sealed and network-isolated:
non-root, all capabilities dropped, no privilege escalation, the repository mounted read-only, and `--network=none`.
It prepends `<cargo-cache>/bin` to `PATH`, so both the tool and a `cargo <subcommand>` form resolve (cargo finds `cargo-<sub>` on `PATH`).

Set `offline: "false"` for a tool that genuinely needs the network, for example `cargo-audit` cloning the advisory database.
The canonical shape is one networked fetch followed by a sealed, offline run.

Setting `docker: "false"` runs the tool on the host instead.
That mode runs `args` on the host, so use it only with trusted input; Docker mode is the default.

## Usage

```yaml
- uses: gronke/cicd-rust/.github/actions/cargo-use@main      # fetch the advisory DB (networked, runs no project build)
  with:
    args: "cargo-audit fetch"
    cargo-cache: .cargo-tools
    offline: "false"
- uses: gronke/cicd-rust/.github/actions/cargo-use@main      # audit sealed, zero egress
  with:
    args: "cargo audit --no-fetch"
    cargo-cache: .cargo-tools
```

Use the same `image` for `cargo-install` and `cargo-use`:
a binary is only guaranteed to run in the image it was built in.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `args` | — (required) | The command line to run, for example `cargo audit --no-fetch`. Word-split inside the container. |
| `docker` | `"true"` | Run sealed in the container; `"false"` runs on the host. |
| `image` | `ghcr.io/gronke/rust-ci:latest` | CI image. Match the one `cargo-install` used (binary ABI). |
| `cargo-cache` | `.cargo-cache` | Host dir mounted read-write as `CARGO_HOME`; its `bin/` is prepended to `PATH`. |
| `offline` | `"true"` | Run with `--network=none`; set `"false"` for a tool that needs the network. |
| `target-dir` | `""` | Optional host dir mounted read-write at `/work/target` for a tool that builds. Empty mounts no target. |
| `working-directory` | `.` | Directory the action runs from. |
| `env-include` / `env-exclude` / `env` | (as `cargo-docker`) | Control which runner env vars are forwarded into the container. |
