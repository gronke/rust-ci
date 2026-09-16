# cargo-fetch

Run `cargo fetch --locked` inside the pinned toolchain image with the network on, filling the registry and git cache under `cargo-cache`.
It is the one networked step of the sealed pipeline: run it once after `build-image`, then `lint-and-test-docker`, `cargo-docker` and `msrv` (with `offline: "true"`) resolve from that cache under `--network=none`.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@v1
- uses: gronke/rust-ci/.github/actions/cargo-fetch@v1
  with:
    working-directory: .
    # git-token: ${{ steps.deps-token.outputs.token }}   # private git dependencies only
- uses: gronke/rust-ci/.github/actions/lint-and-test-docker@v1
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `image` | `rust-ci:latest` | CI image (Rust toolchain, clippy, rustfmt, jq). |
| `working-directory` | `.` | Crate or workspace directory, mounted read-only. |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME` (registry and git cache), mounted read-write. Relative to `working-directory`, or absolute. |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |
| `git-token` | `""` | Token for private git dependencies: authenticates `github.com` fetches as `x-access-token` and sets `CARGO_NET_GIT_FETCH_WITH_CLI=true`. Leave empty for public deps. |

## Notes

- Everything but the network stays sealed: non-root, `--cap-drop=ALL`, `no-new-privileges`, source read-only, no target mount.
- `--locked` requires a committed `Cargo.lock`; a crate without one fails here.
- The fetch retries on transient network output (crates.io timeouts, resets, rate limits); `cargo fetch` is incremental, so a retry resumes from the cache.
- `git-token` is masked with `::add-mask::` and reaches the container as one env-file line, not through `env-include`; the `url.insteadOf` rewrite is written to the container's `HOME` (`/tmp`) and dies with it.
- How to mint a token that can read the dependency repositories: [docs/private-git-dependencies.md](../../../docs/private-git-dependencies.md).
