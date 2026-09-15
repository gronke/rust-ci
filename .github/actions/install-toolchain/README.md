# install-toolchain

Install a Rust toolchain via rustup, add components and targets, and put cargo's `bin` directory on `PATH` for every later step.
Use it at the top of a native job; the sealed actions build their own toolchain image and do not need it.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: gronke/rust-ci/.github/actions/install-toolchain@v1
  with:
    toolchain: stable                 # or a version such as 1.77.2
    components: rustfmt clippy
    targets: wasm32-unknown-unknown   # optional
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `toolchain` | `stable` | Toolchain passed to rustup (e.g. `stable`, `1.77.2`). It becomes the default toolchain. |
| `components` | `""` | Space-separated rustup components to add (e.g. `rustfmt clippy`). |
| `targets` | `""` | Space-separated rustup targets to add (e.g. `x86_64-apple-darwin`). |

## Notes

- With rustup present, the action runs `rustup toolchain install <toolchain> --profile minimal` and `rustup default <toolchain>`.
- On a runner without rustup it downloads the installer (`rustup-init.exe` on Windows, `sh.rustup.rs` elsewhere) and runs it with `--profile minimal --no-modify-path`; the download is retried on transient failures.
- The minimal profile does not include `rustfmt` or `clippy`; request them via `components`.
- The cargo bin directory (`$CARGO_HOME/bin`, default `~/.cargo/bin`; `%USERPROFILE%\.cargo\bin` on a fresh Windows install) is appended to `GITHUB_PATH` in every branch, so a preinstalled rustup that is missing from the runner's persisted `PATH` still leaves later steps with a working `cargo`.
- `rustc --version` and `cargo --version` are printed at the end.
