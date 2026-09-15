# cargo-out-dir

Build a package and output its build script's `OUT_DIR`, the directory where `build.rs` writes generated files.
Use it when a later step needs those files; for a sealed build use [`cargo-docker`](../cargo-docker/README.md) with `out-dir-package`, which translates the path to the host.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-out-dir@v1
  id: out
  with:
    package: my-crate      # optional in a single-package workspace
    profile: release       # optional; empty is dev
    args: "--locked"       # optional
- run: ls "${{ steps.out.outputs.out-dir }}"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `package` | `""` | Package whose build script to resolve (`cargo build -p`). Empty resolves the workspace's sole or root package via `cargo pkgid`; a larger workspace needs the name. |
| `working-directory` | `.` | Directory to run cargo in. |
| `profile` | `""` | Cargo profile (`--profile`), e.g. `release`. Empty is dev. |
| `args` | `""` | Extra `cargo build` args. |

## Outputs

| Output | Description |
| --- | --- |
| `out-dir` | Absolute path of the resolved build script's `OUT_DIR`. |

## Notes

- Needs `jq` on the runner; the action reads cargo's JSON message stream with it.
- The action is the build step: it runs `cargo build --message-format=json-diagnostic-rendered-ansi` and selects the `build-script-executed` message whose `package_id` equals the `cargo pkgid` output exactly.
- A different profile or feature set builds into a different `OUT_DIR`, so pass the same `profile` and `args` as the build that consumes the output rather than resolving after a differently configured build.
- Zero matches (no `build.rs`, or a cargo older than 1.77 whose package ids do not match `cargo pkgid`) or more than one distinct directory fail the step.
- Compiler diagnostics are replayed to the log after the build, so warnings and errors stay readable despite the JSON stream.
