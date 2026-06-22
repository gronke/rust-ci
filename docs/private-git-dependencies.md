# Private git dependencies

`cargo-fetch` can clone `Cargo.toml` git dependencies from **private** repositories when you pass a credential through its `git-token` input — see [Private git dependencies in the README](../README.md#private-git-dependencies-cargo-fetch) for how the token reaches the container's git.
This page covers how to obtain that credential.

The automatic `GITHUB_TOKEN` cannot serve here: its permissions are limited to the repository that contains the workflow, so a dependency in any *other* repository — even a private one in the same organisation — is out of reach.
(The organisation setting that shares actions and reusable workflows across private repos does not help either; it only feeds the runner's internal `uses:` resolution, not a raw clone.)
You need a credential whose scope spans the dependency repositories.

## Which credential

Two work, both passed the same way (`git-token: <value>`):

- A **GitHub App installation token** — recommended. Minted per run, scoped to specific repositories, masked, and auto-revoked when the job ends. Not tied to a person, so it survives offboarding and consumes no seat.
- A **fine-grained PAT** — simpler to set up, but user-owned and long-lived. Fine for a quick start; prefer the App for shared or org-wide use.

## GitHub App (recommended)

### One-time setup

1. Create a GitHub App owned by your organisation. Under **Repository permissions**, grant **Contents: Read** — that is all cargo needs to clone source. (Metadata: Read is added automatically.)
2. Generate a private key; this downloads a `.pem`. Note the App's **Client ID** from its settings page.
3. **Install** the App on the organisation, selecting the private dependency repositories (or all repositories). The installation is the real allow-list — a token can only reach repositories the App is installed on.
4. Store the credentials as **organisation** secrets/variables so every consuming repository shares one setup:
   - Client ID → an organisation **variable** (it is not sensitive), e.g. `DEPS_APP_CLIENT_ID`.
   - The `.pem` → an organisation **secret**, e.g. `DEPS_APP_PRIVATE_KEY`.

   Scope both to the repositories that run the build.

### In the workflow

Mint the token just before `cargo-fetch` and hand the output to `git-token`:

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
  uses: gronke/cicd-rust/.github/actions/cargo-fetch@main
  with:
    git-token: ${{ steps.deps-token.outputs.token }}
```

`repositories` scoping:

- omit `owner` and `repositories` → the token covers only the current repository (not enough here);
- set `owner`, omit `repositories` → all repositories in that owner's installation;
- set both → only the listed repositories — least privilege, the right choice.

The token expires after one hour, is masked in logs by the action, and is revoked automatically in the action's `post` step, so it never lingers.

## Fine-grained PAT (simpler alternative)

Create a fine-grained PAT with **Contents: Read** on each private dependency repository, store it as a secret, and pass it directly:

```yaml
- name: Cargo fetch
  uses: gronke/cicd-rust/.github/actions/cargo-fetch@main
  with:
    git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}
```

It works identically at fetch time; the trade-off is that a PAT is tied to a user account and lives until you rotate or expire it, whereas the App token is short-lived and impersonal.
