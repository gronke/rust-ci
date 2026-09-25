# cargo-install

Install a cargo-based CLI tool (for example `cargo-audit`) into a shared cargo cache, so later steps and other sealed containers can run it: compiled with `cargo install`, or taken from a pinned prebuilt release.
Pair it with [`cargo-use`](../cargo-use/README.md), which prepends the same cache's `bin/` to `PATH` and runs the tool sealed; in host mode the tool is on `PATH` for later steps as well.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-install@v1
  with:
    tool: cargo-audit
    version: "0.21"            # optional; pins the install (and a consumer cache key)
    cargo-cache: .cargo-tools  # shared dir; reuse the same value in cargo-use
    # docker: "true"           # default: install sealed; "false" runs on the host
```

A pinned prebuilt release skips the compile, and in host mode an exact version already present skips the download:

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-install@v1
  with:
    docker: "false"
    tool: cargo-nextest
    version: "0.9.146"
    url: https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-{version}/cargo-nextest-{version}-{target}.tar.gz
    sha256-x86_64: b64617e8640624e8f9ba99819e37d7971154e97836d7ae4774fed4715501a6aa
    sha256-aarch64: 62ae8b4ad034704f67417f8ed8b897566d82359ab44952729b925fb37eeb7622
    cargo-cache: ${{ runner.temp }}/cargo-tools
- run: cargo nextest run --workspace
```

cargo-deny publishes the same shape: `https://github.com/EmbarkStudios/cargo-deny/releases/download/{version}/cargo-deny-{version}-{target}.tar.gz`.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `tool` | (required) | Crate to install. Validated on the host against `^[A-Za-z0-9][A-Za-z0-9_-]*$`. |
| `version` | `""` | Passed as `--version` (an exact version, or a single `^`/`~`/`=` requirement). Empty installs the latest; `url` needs an exact version. |
| `url` | `""` | Release archive (`.tar.gz`) of a prebuilt static binary, with `{version}` and `{target}` placeholders; `{target}` is `x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl`. Set, it replaces the compile in both modes. |
| `sha256-x86_64` | `""` | SHA256 of the x86_64 archive; required with `url`. |
| `sha256-aarch64` | `""` | SHA256 of the aarch64 archive; required with `url`. |
| `bin` | the tool name | Name of the tool's binary, in the archive and on `PATH`. |
| `args` | `""` | Extra flags appended to `cargo install` (for example `--features cli`). Word-split inside the container. |
| `locked` | `"true"` | Append `--locked`. |
| `docker` | `"true"` | Install sealed in the container; `"false"` installs on the host, where `<cargo-cache>/bin` joins `PATH` for later steps. |
| `image` | `rust-ci:latest` | CI image. Use the same image in `cargo-use`. |
| `cargo-cache` | `.cargo-cache` | Host dir mounted read-write as `CARGO_HOME`, relative to `working-directory` or absolute; the tool lands in its `bin/`. |
| `working-directory` | `.` | Directory the action runs from (mounted read-only). |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |

## Outputs

| Output | Description |
| --- | --- |
| `bin-dir` | Host path to the shared bin directory holding the installed tool (`<cargo-cache>/bin`). |
| `installed` | `"true"` when this step installed the tool, `"false"` when host mode found the exact version present already; docker mode always reports `"true"`. |

## Notes

- The install is networked (downloading crates needs egress) but otherwise sealed: non-root, `--cap-drop=ALL`, `no-new-privileges`, repository read-only, no target mount (`cargo install` builds in its own temp dir).
- The binary is written to the host-mounted `CARGO_HOME` (`<cargo-cache>/bin/<tool>`); there is no separate tool directory or extra mount.
- `tool` and `version` are validated on the runner and cross into the container as data, never interpolated into a host shell; `args` is word-split only inside the container.
- `docker: "false"` runs a plain `cargo install` on the runner with `CARGO_HOME` pointed at `cargo-cache`; `args` then word-splits on the host shell, so use it only with trusted input.
- A prebuilt release is downloaded on the runner in both modes and verified against the pin for the runner's architecture before anything is extracted (`_lib/install-release.sh`, which also installs sccache); the binary is taken wherever the archive keeps it and must report the pinned version before it is copied into `<cargo-cache>/bin`.
- In host mode an exact version counts as present when the binary later steps would run reports it in `<bin> --version`: the one in `<cargo-cache>/bin`, which shadows `PATH`, or else the one on `PATH`, where a runner image keeps the tools it bakes. A version requirement always asks cargo.
- Docker mode never runs what the cache holds on the runner, since sealed steps can write to it: a prebuilt release is installed every time, replacing whatever the cache kept under its name, and a `bin` that has become a symbolic link is refused.
- A compiled binary is only guaranteed to run in the image it was built in; use the same `image` for `cargo-install` and `cargo-use`. A prebuilt static musl binary runs in any Linux image of its architecture.
