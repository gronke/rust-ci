# cargo-install

Install a cargo-based CLI tool (for example `cargo-audit`) into a shared cargo cache, so later steps and other sealed containers can run it.
Pair it with [`cargo-use`](../cargo-use/README.md), which prepends the same cache's `bin/` to `PATH` and runs the tool sealed.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-install@v1
  with:
    tool: cargo-audit
    version: "0.21"            # optional; pins the install (and a consumer cache key)
    cargo-cache: .cargo-tools  # shared dir; reuse the same value in cargo-use
    # docker: "true"           # default: install sealed; "false" runs on the host
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `tool` | (required) | Crate to install. Validated on the host against `^[A-Za-z0-9][A-Za-z0-9_-]*$`. |
| `version` | `""` | Passed as `--version` (an exact version, or a single `^`/`~`/`=` requirement). Empty installs the latest. |
| `args` | `""` | Extra flags appended to `cargo install` (for example `--features cli`). Word-split inside the container. |
| `locked` | `"true"` | Append `--locked`. |
| `docker` | `"true"` | Install sealed in the container; `"false"` installs on the host. |
| `image` | `rust-ci:latest` | CI image. Use the same image in `cargo-use`. |
| `cargo-cache` | `.cargo-cache` | Host dir mounted read-write as `CARGO_HOME`; the tool lands in its `bin/`. |
| `working-directory` | `.` | Directory the action runs from (mounted read-only). |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `CARGO_HOME\|RUSTUP_HOME\|CARGO_TARGET_DIR` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim. |

## Outputs

| Output | Description |
| --- | --- |
| `bin-dir` | Host path to the shared bin directory holding the installed tool (`<cargo-cache>/bin`). |

## Notes

- The install is networked (downloading crates needs egress) but otherwise sealed: non-root, `--cap-drop=ALL`, `no-new-privileges`, repository read-only, no target mount (`cargo install` builds in its own temp dir).
- The binary is written to the host-mounted `CARGO_HOME` (`<cargo-cache>/bin/<tool>`); there is no separate tool directory or extra mount.
- `tool` and `version` are validated on the runner and cross into the container as data, never interpolated into a host shell; `args` is word-split only inside the container.
- `docker: "false"` runs a plain `cargo install` on the runner with `CARGO_HOME` pointed at `cargo-cache`; `args` then word-splits on the host shell, so use it only with trusted input.
- A binary is only guaranteed to run in the image it was built in; use the same `image` for `cargo-install` and `cargo-use`.
