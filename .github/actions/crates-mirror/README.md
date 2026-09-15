# crates-mirror

Route cargo's crates-io source through a mirror by writing the source replacement into `$CARGO_HOME/config.toml`.
Use it before the first step that resolves dependencies in a runner-native or `container:` job; the URL comes from the `url` input or from `RUST_CI_CRATES_MIRROR` in the job environment.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/crates-mirror@v1
  # with:
  #   mode: auto             # on | off; auto follows RUST_CI_CRATES_MIRROR in the job env
  #   url: sparse+http://cache.internal:9980/crates/index/
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `mode` | `auto` | `auto` activates when a mirror URL is given, `on` requires one and fails without, `off` changes nothing. |
| `url` | `""` | Explicit mirror URL (`sparse+http(s)://.../`); overrides `RUST_CI_CRATES_MIRROR`. |

## Outputs

| Output | Description |
| --- | --- |
| `active` | `"true"` when the source replacement was written, or was already present and identical. |

## How it works

Cargo's source replacement is config-file-only (cargo#5416), so the action appends a `[source.crates-io]` block with `replace-with = "rust-ci-mirror"` and a `[source.rust-ci-mirror]` block carrying the URL to `$CARGO_HOME/config.toml` (`$HOME/.cargo/config.toml` when `CARGO_HOME` is unset).
The URL must be `sparse+http://` or `sparse+https://` with a limited charset; a missing trailing slash is appended.
`Cargo.lock` keeps the canonical crates.io checksums and cargo verifies every download against them, so the mirror can refuse to serve, never alter what a build consumes.
A second run with the same URL is idempotent; any other existing crates-io replacement in that file fails the step rather than being overwritten.
[docs/self-hosted.md](../../../docs/self-hosted.md) shows how a host provides `RUST_CI_CRATES_MIRROR`.

## Notes

- Hosted runners carry no `RUST_CI_CRATES_MIRROR`, so `auto` keeps fetching from crates.io directly.
- A workspace `.cargo/config.toml` still wins by cargo's own precedence rules.
- The sealed Docker actions are untouched: they pin `CARGO_HOME`, forward `CARGO_.*` only and build offline.
