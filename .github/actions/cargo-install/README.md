# cargo-install

Install a cargo-based CLI tool (for example `cargo-audit`) into a shared cargo cache, so later steps and other sealed containers can run it.

## How it works

By default the install runs inside the pinned image, sealed:
non-root, all Linux capabilities dropped (`--cap-drop=ALL`), no privilege escalation (`--security-opt=no-new-privileges`), and the repository mounted read-only.
The install is networked, because downloading crates needs egress, but every other restriction still applies — `--network=none` is the only seal a networked install drops.

The binary is written to the host-mounted `CARGO_HOME` (`<cargo-cache>/bin/<tool>`), where a later [`cargo-use`](../cargo-use/README.md) — or any sealed run that mounts the same `cargo-cache` — finds it.
The shared "tool directory" is therefore just the existing `CARGO_HOME` mount; there is no extra mount.

## Input safety

`tool` and `version` are allowlisted on the runner, and every input crosses into the container only as data, never interpolated into a host shell, so a crafted value cannot inject a command or a stray flag.
The free-form `args` are word-split only inside the sealed container.

Setting `docker: "false"` wraps a plain `cargo install` on the runner instead.
That mode runs `args` on the host, so use it only with trusted input; Docker mode is the default.

## Usage

```yaml
- uses: gronke/cicd-rust/.github/actions/cargo-install@main
  with:
    tool: cargo-audit
    version: "0.21"            # optional; pins the install (and a consumer cache key)
    cargo-cache: .cargo-tools  # shared dir; reuse the same value in cargo-use
    # docker: "true"           # default: install sealed; "false" runs on the host
```

Use the same `image` for `cargo-install` and `cargo-use`:
a binary is only guaranteed to run in the image it was built in.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `tool` | — (required) | Crate to install. Allowlisted to `^[A-Za-z0-9][A-Za-z0-9_-]*$`. |
| `version` | `""` | Passed as `--version` (an exact version, or a single `^`/`~`/`=` requirement). Empty installs the latest. |
| `args` | `""` | Extra flags appended to `cargo install` (for example `--features cli`). Word-split inside the container. |
| `locked` | `"true"` | Append `--locked`. |
| `docker` | `"true"` | Install sealed in the container; `"false"` installs on the host. |
| `image` | `ghcr.io/gronke/rust-ci:latest` | CI image. Match it in `cargo-use`. |
| `cargo-cache` | `.cargo-cache` | Host dir mounted read-write as `CARGO_HOME`; the tool lands in its `bin/`. |
| `working-directory` | `.` | Directory the action runs from. |
| `env-include` / `env-exclude` / `env` | (as `cargo-docker`) | Control which runner env vars are forwarded into the container. |

## Outputs

| Output | Description |
| --- | --- |
| `bin-dir` | Host path to the shared bin directory holding the installed tool (`<cargo-cache>/bin`). |
