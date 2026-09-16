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
| `git-token` | `""` | Token for private git dependencies: routed as `GIT_CONFIG_*` entries (an `url.insteadOf` rewrite for `git-host`, presented as `git-username`) plus `CARGO_NET_GIT_FETCH_WITH_CLI=true`, which the container's git and cargo read on their own. Leave empty for public dependencies. |
| `git-host` | `github.com` | Git host the token routes, optionally with a port. |
| `git-username` | `x-access-token` | Userinfo name the token is presented under (`oauth2` for GitLab, `x-token-auth` for Bitbucket). |
| `git-path` | `""` | Restrict the rewrite to a namespace under the host; empty routes every fetch on the host. |

## Notes

- Everything but the network stays sealed: non-root, `--cap-drop=ALL`, `no-new-privileges`, source read-only, no target mount.
- `--locked` requires a committed `Cargo.lock`; a crate without one fails here.
- The fetch retries on transient network output (crates.io timeouts, resets, rate limits); `cargo fetch` is incremental, so a retry resumes from the cache.
- `git-token` is validated (charset, host, username, path) and masked before use, and reaches the container as `GIT_CONFIG_*` env-file lines, the same shape `route-git-token` exports for jobs outside the container; nothing is written to a gitconfig file.
- How to mint a token that can read the dependency repositories: [docs/private-git-dependencies.md](../../../docs/private-git-dependencies.md).
