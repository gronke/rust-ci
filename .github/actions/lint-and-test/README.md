# lint-and-test

Run `cargo fmt --all -- --check`, `cargo clippy --workspace ... -- -D warnings` and `cargo test --workspace` for one feature set, natively on the runner.
Use it after [`install-toolchain`](../install-toolchain/README.md) with the `rustfmt clippy` components; [`lint-and-test-docker`](../lint-and-test-docker/README.md) is the sealed equivalent.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/install-toolchain@v1
  with:
    components: rustfmt clippy
- uses: gronke/rust-ci/.github/actions/lint-and-test@v1
  with:
    features: "--all-features"   # optional; empty is the default feature set
    fmt: "false"                 # run fmt on one matrix leg only
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory to run cargo in. |
| `features` | `""` | Feature flag applied to clippy and test (e.g. `--all-features`, `--no-default-features`). Empty means the default feature set. |
| `fmt` | `"true"` | Run `cargo fmt --all -- --check` (independent of the feature set). |
| `clippy` | `"true"` | Run clippy with `-D warnings`. |
| `test` | `"true"` | Run `cargo test`. |
| `clippy-args` | `--all-targets` | Extra clippy args, placed before `-- -D warnings`. |
| `test-args` | `""` | Extra `cargo test` args. |

## Notes

- The exact commands are `cargo fmt --all -- --check`, `cargo clippy --workspace <clippy-args> <features> -- -D warnings` and `cargo test --workspace <features> <test-args>`.
- `features`, `clippy-args` and `test-args` are word-split on whitespace; shell quoting inside them is not interpreted.
- `fmt` does not depend on `features`; in a matrix, enable it on one leg and set `fmt: "false"` on the others.
- Each command runs in its own collapsible log group.
- The same script runs inside [`lint-and-test-docker`](../lint-and-test-docker/README.md), which fixes `--all-targets` and `--locked` and adds `--offline` from its `offline` input; here neither `--locked` nor `--offline` is passed unless `clippy-args` or `test-args` carry them.
