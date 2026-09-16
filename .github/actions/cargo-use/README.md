# cargo-use

Run a tool that [`cargo-install`](../cargo-install/README.md) placed in the shared cargo cache, from a sealed container with `--network=none` by default.
Use it after `cargo-install` with the same `cargo-cache` and `image`; `<cargo-cache>/bin` is prepended to `PATH`, so both `cargo-audit ...` and the `cargo audit ...` subcommand form resolve.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-use@v1      # fetch the advisory DB (networked, no project build)
  with:
    args: "cargo-audit fetch"
    cargo-cache: .cargo-tools
    offline: "false"
- uses: gronke/rust-ci/.github/actions/cargo-use@v1      # audit sealed, no egress
  with:
    args: "cargo audit --no-fetch"
    cargo-cache: .cargo-tools
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `args` | (required) | The command line to run, for example `cargo audit --no-fetch`. Word-split inside the container. |
| `docker` | `"true"` | Run sealed in the container; `"false"` runs on the host. |
| `image` | `rust-ci:latest` | CI image. Use the same one `cargo-install` used. |
| `cargo-cache` | `.cargo-cache` | Host dir mounted read-write as `CARGO_HOME`; its `bin/` is prepended to `PATH`. |
| `offline` | `"true"` | Run with `--network=none`; `"false"` for a tool that needs the network. |
| `target-dir` | `""` | Optional host dir mounted read-write at `/work/target` (plus `CARGO_TARGET_DIR`) for a tool that builds. Empty mounts no target. |
| `working-directory` | `.` | Directory the action runs from (mounted read-only). |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |

## Notes

- The seal is the shared one: non-root, `--cap-drop=ALL`, `no-new-privileges`, repository read-only; `offline` toggles only `--network=none`.
- A tool that reaches the network under `offline: "true"` fails; the pattern is one networked fetch, then a sealed offline run.
- `docker: "false"` runs the tool from `<cargo-cache>/bin` on the runner; `args` then word-splits on the host shell, so use it only with trusted input.
- A binary is only guaranteed to run in the image it was built in; match `image` between `cargo-install` and `cargo-use`.
