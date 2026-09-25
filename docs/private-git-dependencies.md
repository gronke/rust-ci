# Private git dependencies

`cargo-fetch` can clone `Cargo.toml` git dependencies from **private** repositories when you pass a credential through its `git-token` input; see the [`cargo-fetch` README](../.github/actions/cargo-fetch/README.md) for how the token reaches the container's git.
This page covers how to obtain that credential.

The automatic `GITHUB_TOKEN` cannot serve here: its permissions are limited to the repository that contains the workflow, so a dependency in any *other* repository, even a private one in the same organisation, is out of reach.
(The organisation setting that shares actions and reusable workflows across private repos does not help either; it only feeds the runner's internal `uses:` resolution, not a raw clone.)
You need a credential whose scope spans the dependency repositories.

## Which credential

Two work, both passed the same way (`git-token: <value>`):

- A **GitHub App installation token** (recommended).
  Minted per run, scoped to specific repositories, masked, and revoked when the job ends.
  Not tied to a person, so it survives offboarding and consumes no seat.
- A **fine-grained PAT**: simpler to set up, but user-owned and long-lived.
  Fine for a quick start; prefer the App for shared or org-wide use.

## GitHub App (recommended)

### One-time setup

1. Create a GitHub App owned by your organisation.
   Under **Repository permissions**, grant **Contents: Read**; that is all cargo needs to clone source.
   (Metadata: Read is added automatically.)
2. Generate a private key; this downloads a `.pem`.
   Note the App's **Client ID** from its settings page.
3. **Install** the App on the organisation, selecting the private dependency repositories (or all repositories).
   The installation is the real allow-list: a token can only reach repositories the App is installed on.
4. Store the credentials as **organisation** secrets/variables so every consuming repository shares one setup:
   - Client ID → an organisation **variable** (it is not sensitive), e.g. `DEPS_APP_CLIENT_ID`.
   - The `.pem` → an organisation **secret**, e.g. `DEPS_APP_PRIVATE_KEY`.

   Scope both to the repositories that run the build.

### In the workflow

Mint the token just before `cargo-fetch` and hand the output to `git-token`:
For a host other than GitHub, add `git-host` (and `git-username`, `oauth2` on GitLab); `git-path` narrows the rewrite to one namespace.

```yaml
- name: Mint an installation token for private deps
  id: deps-token
  uses: actions/create-github-app-token@v3        # GitHub-owned; consider pinning to a full SHA
  with:
    client-id:   ${{ vars.DEPS_APP_CLIENT_ID }}
    private-key: ${{ secrets.DEPS_APP_PRIVATE_KEY }}
    owner: ${{ github.repository_owner }}
    repositories: |
      private-dep-a
      private-dep-b
    permission-contents: read       # narrow the minted token to read-only contents

- name: Cargo fetch
  uses: gronke/rust-ci/.github/actions/cargo-fetch@v1
  with:
    git-token: ${{ steps.deps-token.outputs.token }}
```

`repositories` scoping:

- omit `owner` and `repositories` → the token covers only the current repository (not enough here);
- set `owner`, omit `repositories` → all repositories in that owner's installation;
- set both → only the listed repositories (least privilege, the right choice).

The token expires after one hour, is masked in logs by the action, and is revoked in the action's `post` step, so it never lingers.

### Without the sealed container

A job that runs plain `cargo build` or `git clone` on the runner (no `cargo-fetch`, no seal) routes a token with [`route-git-token`](../.github/actions/route-git-token/README.md), which mints the GitHub App token itself:

```yaml
- name: Route private git fetches through an App token
  uses: gronke/rust-ci/.github/actions/route-git-token@v1
  with:
    app-client-id: ${{ vars.DEPS_APP_CLIENT_ID }}
    app-private-key: ${{ secrets.DEPS_APP_PRIVATE_KEY }}
    app-repositories: private-dep-a,private-dep-b
    path: ${{ github.repository_owner }}   # optional; empty routes the whole host
```

A token minted elsewhere, a fine-grained PAT for example, goes into `token` instead of the `app-*` inputs.
`remaps` covers a dependency pinned at a URL outside the routed namespace: a line `https://github.com/upstream/dep=my-org/dep-mirror` fetches it from the mirror with the same token.

The action is not GitHub-bound: `host:` (with an optional port) and `username:` route any authenticated https git host; a self-hosted GitLab takes `host: gitlab.example.com` with `username: oauth2` and a nested `path: group/sub-group`.
Only the App minting is GitHub-specific; any other forge's token comes in through `token`.

It exports the `url.insteadOf` rewrites as `GIT_CONFIG_*` environment entries (they die with the job; nothing lands in a gitconfig file, which matters on self-hosted runners) and sets `CARGO_NET_GIT_FETCH_WITH_CLI` so cargo's fetches honor them.
The rewrite is a transport detail: scope the token, as above; a rewrite for a repository the token cannot read fails exactly like no rewrite at all.

## Fine-grained PAT (simpler alternative)

Create a fine-grained PAT with **Contents: Read** on each private dependency repository, store it as a secret, and pass it directly:

```yaml
- name: Cargo fetch
  uses: gronke/rust-ci/.github/actions/cargo-fetch@v1
  with:
    git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}
```

It works identically at fetch time; the trade-off is that a PAT is tied to a user account and lives until you rotate or expire it, whereas the App token is short-lived and impersonal.
