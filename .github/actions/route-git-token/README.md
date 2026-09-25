# route-git-token

Route git fetches on the runner through a short-lived token: `url.insteadOf` rewrites that authenticate https fetches, exported as `GIT_CONFIG_*` environment entries via `GITHUB_ENV`, plus `CARGO_NET_GIT_FETCH_WITH_CLI=true` so cargo fetches through the git CLI, which honors the rewrites (cargo's libgit2 path does not).
Use it for jobs that run plain `cargo build` or `git clone` on the runner; [`cargo-fetch`](../cargo-fetch/README.md)'s `git-token` input is the sealed equivalent (see [Private git dependencies](../../../docs/private-git-dependencies.md)).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/route-git-token@v1
  with:
    app-client-id: ${{ vars.DEPS_APP_CLIENT_ID }}
    app-private-key: ${{ secrets.DEPS_APP_PRIVATE_KEY }}
    app-repositories: private-dep-a,private-dep-mirror
    path: ${{ github.repository_owner }}   # optional; empty routes the whole host
    remaps: |
      https://github.com/upstream/dep=${{ github.repository_owner }}/private-dep-mirror
- run: cargo build --locked
```

A token minted elsewhere goes into `token` instead of the `app-*` inputs.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `token` | `""` | Token the fetches authenticate with; read access on the repositories the job needs. Masked in logs. Empty when the `app-*` inputs mint it. |
| `host` | `github.com` | Git host to route, optionally with a port (`my.gitlab.example:8443`). |
| `username` | `x-access-token` | Userinfo name the token is presented under (the host's convention, not a real user). GitHub App tokens and PATs: `x-access-token`; GitLab OAuth: `oauth2`; Bitbucket: `x-token-auth`. |
| `path` | `""` | Namespace under the host to restrict the rewrite to (an owner, or a nested group like `my-group/sub-group`). Empty routes every fetch on the host, matching `cargo-fetch`'s in-container behavior. |
| `remaps` | `""` | Lines of `from=to`, each sending fetches of an https URL to a repository path on the host with the token presented, for a dependency pinned at a URL outside the routed namespace. |
| `app-client-id` | `""` | Client ID of a GitHub App; with `app-private-key`, the action mints a contents-read installation token through `actions/create-github-app-token` in place of `token`. |
| `app-private-key` | `""` | Private key of that App; pass a secret. |
| `app-owner` | the repository owner | Owner of the App installation the token is minted for. |
| `app-repositories` | `""` | Comma- or newline-separated repositories the minted token covers; empty covers every repository of the owner's installation. |

## Outputs

| Output | Description |
| --- | --- |
| `token` | The token the rewrites present, minted or passed in; masked in logs. |

## Notes

- The entries are built by `.github/actions/_lib/git-route.sh`, which `cargo-fetch` and `publish-dry-run` also use for their `git-token`, so the validation and the rewrite shape are identical on the runner and inside the container.
- The rewrites live in `GIT_CONFIG_KEY_n`, `GIT_CONFIG_VALUE_n` and `GIT_CONFIG_COUNT`, not in a gitconfig file: they die with the job, which matters on self-hosted runners.
- A second invocation appends behind the entries an earlier one exported (`GIT_CONFIG_COUNT` is the cursor), so several hosts or namespaces can be routed in one job.
- git applies the longest matching `insteadOf` value, so a remap outranks the namespace rewrite; `from` is a URL prefix, so `https://github.com/upstream/dep` also covers `dep.git`.
- Exactly one token source is required: `token`, or `app-client-id` with `app-private-key`; the minted token expires after an hour and `actions/create-github-app-token` revokes it at job end.
- `token` must match `^[A-Za-z0-9._~+=-]+$`; a value with whitespace or one of `@:/?#%` is refused before it is masked or exported, because it is interpolated into a `GITHUB_ENV` line and a git URL.
- `host`, `username`, `path` and every remap are validated (host[:port], userinfo, namespace-path and https-URL charsets); a refused input exports nothing.
- Every use resolves `actions/create-github-app-token` at "Set up job", even with `token` passed directly, because the runner resolves a nested `uses` before its `if`; runners with restricted action sources need it available.
- `path` is about predictability, not security: a rewrite for a repository the token cannot read fails exactly like no rewrite at all, so scope the token where it is minted.
