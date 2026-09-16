# route-git-token

Route git fetches on the runner through a short-lived token: an `url.insteadOf` rewrite that authenticates https fetches, exported as `GIT_CONFIG_*` environment entries via `GITHUB_ENV`, plus `CARGO_NET_GIT_FETCH_WITH_CLI=true` so cargo fetches through the git CLI, which honors the rewrite (cargo's libgit2 path does not).
Use it for jobs that run plain `cargo build` or `git clone` on the runner; [`cargo-fetch`](../cargo-fetch/README.md)'s `git-token` input is the sealed equivalent, and minting the token stays with the caller (see [Private git dependencies](../../../docs/private-git-dependencies.md)).

## Usage

```yaml
- uses: actions/create-github-app-token@v3
  id: deps-token
  with:
    client-id: ${{ vars.DEPS_APP_CLIENT_ID }}
    private-key: ${{ secrets.DEPS_APP_PRIVATE_KEY }}
    owner: ${{ github.repository_owner }}
    repositories: private-dep-a
    permission-contents: read
- uses: gronke/rust-ci/.github/actions/route-git-token@v1
  with:
    token: ${{ steps.deps-token.outputs.token }}
    path: ${{ github.repository_owner }}   # optional; empty routes the whole host
- run: cargo build --locked
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `token` | (required) | Token the fetches authenticate with; read access on the repositories the job needs. Masked in logs. |
| `host` | `github.com` | Git host to route, optionally with a port (`my.gitlab.example:8443`). |
| `username` | `x-access-token` | Userinfo name the token is presented under (the host's convention, not a real user). GitHub App tokens and PATs: `x-access-token`; GitLab OAuth: `oauth2`; Bitbucket: `x-token-auth`. |
| `path` | `""` | Namespace under the host to restrict the rewrite to (an owner, or a nested group like `my-group/sub-group`). Empty routes every fetch on the host, matching `cargo-fetch`'s in-container behavior. |

## Notes

- The entries are built by `.github/actions/_lib/git-route.sh`, which `cargo-fetch` and `publish-dry-run` also use for their `git-token`, so the validation and the rewrite shape are identical on the runner and inside the container.

- The rewrite lives in `GIT_CONFIG_KEY_n`, `GIT_CONFIG_VALUE_n` and `GIT_CONFIG_COUNT`, not in a gitconfig file: it dies with the job, which matters on self-hosted runners.
- A second invocation appends behind the entries an earlier one exported (`GIT_CONFIG_COUNT` is the cursor), so several hosts or namespaces can be routed in one job.
- `token` must match `^[A-Za-z0-9._~+=-]+$`; a value with whitespace or one of `@:/?#%` is refused before it is masked or exported, because it is interpolated into a `GITHUB_ENV` line and a git URL.
- `host`, `username` and `path` are validated against a host[:port], userinfo and namespace-path charset; a refused input exports nothing.
- `path` is about predictability, not security: a rewrite for a repository the token cannot read fails exactly like no rewrite at all, so scope the token where it is minted.
