# cargo-docker

Run one cargo command inside the pinned toolchain image, sealed: non-root, all capabilities dropped, no privilege escalation, the working directory mounted read-only and, by default, `--network=none` with `cargo --offline`.
Use it for a build, check or test that `lint-and-test-docker` does not cover; run `cargo-fetch` first to fill the cache it resolves from, and see [docs/sealed-builds.md](../../../docs/sealed-builds.md) for the seal itself.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-fetch@v1        # the one networked step
- id: build
  uses: gronke/rust-ci/.github/actions/cargo-docker@v1
  with:
    args: "build --release --locked"      # no --offline here; `offline` adds it
    out-dir-package: my-app               # optional: expose build.rs's OUT_DIR
    out-dir-args: "--release --locked"    # mirror the main build's profile
- run: cp -r "${{ steps.build.outputs.out-dir }}/dist"/. site/
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `image` | `rust-ci:latest` | CI image (Rust toolchain, clippy, rustfmt, jq). |
| `working-directory` | `.` | Crate or workspace directory, mounted read-only at `/work`. |
| `args` | (required) | The cargo command and flags, e.g. `test --locked -- --nocapture`. Do not include `--offline`. |
| `target-dir` | `target` | Host dir for the cargo target, mounted read-write at `/work/target`. Relative to `working-directory`, or absolute. |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME`, mounted read-write; populated by `cargo-fetch`. |
| `offline` | `"true"` | `--network=none` plus `cargo --offline`. `"false"` runs networked and fetches as it builds. |
| `out-dir-package` | `""` | Package whose build-script `OUT_DIR` to resolve and expose as `out-dir`. Needs a non-empty `target-dir`. |
| `out-dir-args` | `""` | Extra args for the resolve build; mirror the main build's profile and features. Do not include `--offline`. |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |

## Outputs

| Output | Description |
| --- | --- |
| `out-dir` | Host path of the `out-dir-package` build script's `OUT_DIR`; empty when `out-dir-package` is unset. |

## Notes

- `--offline` is inserted before the subcommand, so `args` may end in `-- <arguments>` for the test binary.
- `out-dir-package` runs two more sealed invocations against the warm target: `cargo pkgid -p <package>`, then `cargo build -p <package> <out-dir-args> --message-format=json-diagnostic-rendered-ansi`; the `build-script-executed` message whose `package_id` equals the pkgid exactly names the `OUT_DIR`.
- Exact package-id matching needs cargo 1.77 or newer in the image (Package ID Spec in `cargo pkgid` and in JSON messages); an older cargo fails with "no build-script OUT_DIR".
- The resolve build uses `out-dir-args`, not `args`, so an empty value after a `--release` main build compiles and resolves the dev profile's directory instead.
- The container path `/work/target/...` is translated to the host side of `target-dir`; a result outside the target mount is refused.
