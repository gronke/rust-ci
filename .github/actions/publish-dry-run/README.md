# publish-dry-run

Gate a crates.io release in two halves inside the pinned toolchain image: a networked prep that runs no dependency code, then a sealed verify-build under `--network=none`.
Use it on a release tag before `cargo-publish`; `check-release-readiness` runs similar checks on the runner without Docker.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@v1
- uses: gronke/rust-ci/.github/actions/publish-dry-run@v1
  with:
    package: my-crate          # required for a workspace with more than one member
    # expected-version: 1.2.3  # defaults to the pushed <package>-v* or v* tag
    # require-deps-published: "true"   # multi-crate workspaces: path deps must be live on crates.io
    # git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}   # private git dependencies only
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `image` | `rust-ci:latest` | CI image (Rust toolchain, jq, curl). |
| `working-directory` | `.` | Crate or workspace directory, mounted read-only. |
| `target-dir` | `target` | Host dir for the cargo target, mounted read-write; also carries the prep-to-verify handoff file. |
| `cargo-cache` | `.cargo-cache` | Host dir for `CARGO_HOME`, mounted read-write; warmed by the prep step. |
| `package` | `""` | Package to check. Required when `cargo metadata --no-deps` lists more than one package. |
| `expected-version` | `""` | Version the crate must declare. Empty derives it from a `refs/tags/<package>-v*` or `refs/tags/v*` ref; with neither, the check is skipped with a notice. |
| `require-deps-published` | `"false"` | Probe crates.io for every workspace path dependency at the version the manifest requires; a 404 fails the run. |
| `git-token` | `""` | Token for private git dependencies during the prep fetch: routed as `GIT_CONFIG_*` entries (an `url.insteadOf` rewrite for `git-host`, presented as `git-username`) plus `CARGO_NET_GIT_FETCH_WITH_CLI=true`, which the container's git and cargo read on their own. Leave empty for public dependencies. |
| `git-host` | `github.com` | Git host the token routes, optionally with a port. |
| `git-username` | `x-access-token` | Userinfo name the token is presented under (`oauth2` for GitLab, `x-token-auth` for Bitbucket). |
| `git-path` | `""` | Restrict the rewrite to a namespace under the host; empty routes every fetch on the host. |
| `env-include` | `CARGO_.*` | POSIX ERE of runner variable names to forward, anchored full-name. |
| `env-exclude` | `""` | Names dropped from the included set; exclusion wins. |
| `env` | `""` | Literal `KEY=VALUE` lines forwarded verbatim; a bare `NAME` forwards the runner's value. |

## Notes

- Prep (networked, no build): `cargo fetch --locked`, package selection, tag/version assert, the crates.io not-already-published probe, `cargo publish --dry-run --no-verify --locked`, `cargo package --no-verify --locked`, then a second `cargo fetch` against the packaged manifest so registry copies of path dependencies are in the cache.
- Verify (sealed): `cargo package --list --offline --locked` and `cargo package --offline --locked`; `cargo publish --dry-run` cannot run here because it always contacts the registry, which `--offline` rejects.
- A package with `publish = false` (or a `publish` list without `crates-io`) gets only the fetch and the tag/version assert in the prep and skips the verify-build with a notice.
- The prep fails when the `.crate` would contain a cargo build tree or cargo home; keep `target-dir` and `cargo-cache` outside the crate directory (absolute paths work) or exclude them in `Cargo.toml`.
- The crates.io probes warn instead of failing on a network error; HTTP 200 on the crate itself (already published) and, with `require-deps-published`, HTTP 404 on a dependency fail the run.
