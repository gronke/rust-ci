# The release flow

How a repository goes from `[Unreleased]` changelog entries to a published GitHub release, and for a crate to a crates.io upload, composed from the eight release actions in this repository:
[`changelog`](../.github/actions/changelog/README.md), [`cut-release`](../.github/actions/cut-release/README.md), [`check-release-readiness`](../.github/actions/check-release-readiness/README.md), [`draft-release`](../.github/actions/draft-release/README.md), [`release-guidance`](../.github/actions/release-guidance/README.md), [`require-signed-tag`](../.github/actions/require-signed-tag/README.md), [`publish-draft-release`](../.github/actions/publish-draft-release/README.md), and [`cargo-publish`](../.github/actions/cargo-publish/README.md).
Every gate is a step a repository can replace or drop.

The flow is branch-based: every push of a `release/vX.Y.Z` branch rebuilds a draft pre-release, and one human-signed annotated `vX.Y.Z` tag publishes that draft.
Drafts are invisible and mutable, and candidate marker tags reserve nothing, so the loop can run, fail, and be deleted without consequence.
Publication is the one irreversible step: a published release is immutable and its tag name stays consumed even if the release is deleted, and a crates.io upload can only be yanked.

[`.github/workflows/release.yml`](../.github/workflows/release.yml) and [`.github/workflows/cut.yml`](../.github/workflows/cut.yml) are the reference pipeline; this repository releases itself with them.

## Runbook

1. Cut: dispatch the cut workflow on the default branch; on a repository without a Cargo.toml, type the version into the dispatch form.
   The cut rewrites `[Unreleased]` into the released section, pushes `release/vX.Y.Z`, opens the merge-back pull request and dispatches the pipeline on the branch.
2. Candidate build and review: the build the cut dispatched on `release/vX.Y.Z` creates the draft pre-release and pushes a `vX.Y.Z-rc1` marker on the built commit; the seal in step 5 needs at least one marker.
   Review the draft, its assets and notes; each further push to the branch refreshes the same draft as the next candidate.
   The run's step summary carries the sign-and-push commands with the marker and commit filled in.
3. Merge-back: merge the pull request the cut opened so that the default-branch tip carries the released section with the newest candidate's tree.
   A rebase or fast-forward merge does that while the default branch has not moved; if it has, rebase the release branch, let the candidate rebuild, then merge.
   The moving major only ever points at a commit on the default branch, so this step precedes the tag.
4. Sign and push the tag on the merged tip (a repository admin holding a release-signing key registered with their GitHub account):

   ```sh
   git fetch origin 'refs/tags/vX.Y.Z-rc*:refs/tags/vX.Y.Z-rc*'
   git tag -s -F <(git tag -l --format='%(contents)' vX.Y.Z-rcN) vX.Y.Z <commit>
   git push origin vX.Y.Z
   ```

   `<commit>` is the default-branch tip after the merge-back; it carries the newest marker's tree, which is what the seal compares.
   The signed tag copies the marker's message, the changelog section rendered for the version.
   Push the tag by name; never `git push --tags`, which pushes every local tag along.
   Never publish the draft by hand: GitHub would create an unsigned tag that fails the gate after the release is already live.
5. The tag pipeline: the push runs the gate (version coherence, `require-signed-tag`, the seal against the newest marker's tree) and then the final path (the draft flip, the moving major, and for a crate the registry upload behind the gate).
6. Delete the release branch.

## The version ladder

`changelog`, `cut-release` and `check-release-readiness` read the version the same way: the explicit `version` input, else Cargo.toml through `cargo metadata`, else (for `check-release-readiness` and the `notes` mode) the changelog's newest released section; `cut-release` needs the input on a repository without a crate.
The candidate and publish actions take the version as a required input, and `cargo-publish` reads it from Cargo.toml only.
The first change after a release bumps the version; later pull requests in the same window ride along.
The `changelog` action's `check` mode enforces this on every pull request: while `CHANGELOG.md` carries `[Unreleased]` entries, the version must exceed the greatest release tag by SemVer precedence (`1.0.0-rc1 < 1.0.0`), and a `**Breaking` entry demands a minor bump on 0.x or a major bump from 1.x.
A multi-member workspace passes `package:` to name the crate whose version is the release version; the tag convention is repo-wide `v*`, and each action invocation checks exactly one package.
Without a Cargo.toml, `check` degrades to section/tag coherence: the newest released section must carry its tag, warning when it does not.

### Release-candidate versions

A version with a pre-release suffix (`1.0.0-rc1`) is a release in its own right: the full flow, a `v1.0.0-rc1` tag, and a GitHub release flagged pre-release.
`check` refuses a pre-release version whose `[Unreleased]` carries `### Added`, `### Removed`, or a `**Breaking` entry; feature work moves the version to the next regular release, while `### Fixed` and `### Security` entries iterate `rc2`, `rc3`.
A stable version's baseline skips `-rcN` tags, since candidate markers reserve nothing.
Number candidates `-rc.9`, `-rc.10` when double digits are in reach: SemVer compares `rc9` and `rc10` lexically, so `rc10` orders below `rc9`.
Marker tags append `-rcN` to the tag name, so `v1.0.0-rc1-rc2` marks the second build of the `1.0.0-rc1` release.

## Phases

**Cut** (`cut-release`): a `workflow_dispatch` on the default branch rewrites `[Unreleased]` into `[X.Y.Z] - <date>`, stamps `CITATION.cff` where one exists, pushes `release/vX.Y.Z`, opens the merge-back pull request, and dispatches the release pipeline on the branch, since a push made with the workflow token triggers no workflows.
It refuses an empty `[Unreleased]` section and an existing release branch.

**Gate** (`check-release-readiness`, `require-signed-tag`, `publish-draft-release` with `seal-only`): every run checks that the ref-derived version equals the declared one, and for a publishable crate that `cargo publish --dry-run` passes and the version is not on crates.io.
On a tag run `require-signed-tag` refuses a lightweight or unverified tag, and the seal-only step fails a tag that does not carry the newest marker's tree, both before any artifact job runs.

**Candidate** (`draft-release`, `release-guidance`): every push to the release branch renders the changelog section into `release-notes.md`, creates or refreshes the `vX.Y.Z` draft pre-release, pushes an annotated unsigned `vX.Y.Z-rcN` marker on the built commit carrying the same notes as its message, and writes the sign-and-push runbook into the step summary.

**Publish** (`publish-draft-release`): the signed `vX.Y.Z` tag arrives, and the tag run seals it against the newest marker by tree, flips the draft live (a stable version sheds the pre-release flag), and with `moving-major` advances `v<MAJOR>` to the highest stable release in its line.

**Registry** (`cargo-publish`): on the same tag run, behind `require-signed-tag`, the crate is uploaded with the Trusted Publishing token from `rust-lang/crates-io-auth-action`; [`cargo-publish`'s README](../.github/actions/cargo-publish/README.md) has the three-step snippet.

**Merge-back**: the pull request the cut opened lands on the default branch; on a repository without a Cargo.toml, `check` warns until the newest released section carries its tag.

## Verify a release from a checkout

The signature GitHub verified is on the tag object, so anyone with the maintainer's published key can check it offline:

```sh
git fetch origin 'refs/tags/vX.Y.Z:refs/tags/vX.Y.Z'
git verify-tag vX.Y.Z
```

For an OpenPGP signature import the maintainer's published key first; for an SSH signature point `gpg.ssh.allowedSignersFile` at a file listing the maintainer's signing key.
`git tag -v vX.Y.Z` prints the tag message, the changelog section, alongside the verification.

## Rulesets

A tag ruleset with `required_signatures` refuses only pushes that introduce unsigned commits; an annotated or lightweight tag on already-pushed history passes it whether or not the tag object is signed.
The signature is therefore enforced by the pipeline gate (`require-signed-tag`), and the ruleset's job is to restrict who creates release tags:

```sh
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-maintainer-only.json
```

`tags-maintainer-only` restricts creation, update and deletion of every tag to repository admins (the bypass actor), except the `v*-rc*` markers `draft-release` pushes and the bare `v<MAJOR>` tags `publish-draft-release` moves with the workflow token.

## Repository settings the flow relies on

- Settings > Actions > General: "Allow GitHub Actions to create and approve pull requests", or `cut-release` fails at the merge-back.
- The `tags-maintainer-only` ruleset above, or one of the same shape: Actions may create `v*-rc*` markers (and the bare `v<MAJOR>` tags when `moving-major` is on), final `v*` tags are for admins.
- A branch ruleset restricting `release/v*` creation and pushes to release managers and Actions.
- A release-signing key (OpenPGP or SSH) registered with the GitHub account that pushes the tag; GitHub verifies the tag object against the keys registered to the account whose verified email matches the tagger identity.
- A `release` environment on the publish job, with required reviewers where a human pause before publication is wanted.
- The merge-back pull request triggers no CI when the cut ran with the workflow token; a machine-user or App token through `cut-release`'s `token` and `git-user-*` inputs does.
- Trusted Publishing on crates.io for the publishing workflow, plus `id-token: write` on the publish job.

## When a gate refuses

| Refusal | What happened, what to do |
| --- | --- |
| lightweight tag, or not a verified signed tag | Recreate the tag annotated (`git tag -s`) with a key your GitHub account knows and force-push it by name; the draft is still a draft, nothing is consumed. |
| does not carry the content the last build sealed | The branch moved after the candidate, or the merge-back rebase brought other changes; re-tag the newest marker commit (or a tree-identical tip), or push the branch and let a new candidate build. |
| tag/expected version != declared version | The ref name, the crate version and the changelog section must agree; fix the branch content. |
| already published on crates.io | A published version cannot be replaced; bump the version and cut again. |
| GH013 on the marker push | A tag ruleset restricts `v*-rc*`; exclude the markers from every creation-restricting tag rule. |
| GH013 on the final tag push | The ruleset restricts final `v*` tags to admins; push from an account the bypass names. |
| no candidate marker for vX.Y.Z | The tag arrived without a candidate build; cut a release branch first. |
| the cut refuses | `[Unreleased]` is empty, or the release branch already exists. |
| feature content on a pre-release version | `### Added`, `### Removed` or `**Breaking` while the version declares `-rcN`; move the version to the next regular release. |
