# The release flow

How a crate goes from `[Unreleased]` entries to a published GitHub release sealed by a signed tag, composed from the release actions in this repository:
[`changelog`](../README.md#changelog), [`cut-release`](../README.md#cut-release), [`check-release-readiness`](../README.md#check-release-readiness), [`require-signed-tag`](../README.md#require-signed-tag), and [`release-guidance`](../README.md#release-guidance).

The flow is branch-based: every push of a `release/vX.Y.Z` branch rebuilds a **draft** pre-release, and the signed `vX.Y.Z` tag publishes that draft, exactly once.
Drafts are invisible and mutable, and candidate marker tags reserve nothing, so the whole loop can run, fail, and be deleted without consequence.
Publication is the one irreversible step: a published release is immutable — assets frozen, tag locked, and the tag name permanently consumed even if the release is deleted afterwards.

## The release manager's runbook

The signed path (`sign-tags: manual`, the mode an active signature-requiring tag ruleset implies), start to finish:

1. Dispatch **Cut release** on the default branch — on a repository without a Cargo.toml, type the version into the dispatch form.
2. Watch the candidate build on `release/vX.Y.Z`: it refreshes the draft pre-release with the rendered notes and seals a `vX.Y.Z-rcN` marker on the built commit.
3. On a rebase-only repository, merge the merge-back pull request now (one "Approve and run" click on its CI when the cut ran with the workflow token) — the tree seal accepts the rebased tip, and your tag will live on the default branch.
4. Run the two commands from the run's guidance summary: fetch the markers, then `git tag -s -F <(…marker message…) vX.Y.Z <commit>` on the marker's commit — or the rebase-merged tip — and push the tag by name.
5. The tag push runs the final path: signature gate, tree seal, draft flip, and the moving major where enabled.
6. For a crates.io crate, `cargo publish` stays a deliberate manual step; then delete the release branch.

When something refuses:

- The marker push is rejected (GH013) — the tag ruleset must let Actions create unsigned `v*-rc*`; import [`tags-signed.json`](../.github/rulesets/tags-signed.json) and [`tags-maintainer-only.json`](../.github/rulesets/tags-maintainer-only.json), which carry the exclusions.
- The seal refuses your tag — the branch moved past the candidate, or the tag's tree differs from the newest marker's; push the intended tip as the release branch, let the candidate reseal it, and `gh run rerun <run-id> --failed` on the tag run.
- The full refusal list is at the end of this guide.

## Versions come from Cargo.toml

Every stage reads the version the manifest declares (through `cargo metadata`); nothing else names a version.
The first change after a release bumps the version; later pull requests in the same window ride along without bumping again.
The `changelog` check enforces this on every pull request: while `CHANGELOG.md` carries `[Unreleased]` entries, the crate version must exceed the last released baseline by SemVer precedence, and a `**Breaking:**` entry demands more than a patch bump.

### Repositories without a Cargo.toml

The flow releases repositories that are not crates — this one dogfoods it.
The version ladder everywhere is: the explicit `version` input, else Cargo.toml, else the changelog's newest released section (the manifest equivalent of a repository whose only version record is its changelog).
The cut names the version as a `workflow_dispatch` input, `check-release-readiness` and `notes` fall back to the newest released section, and the pull-request `check` — with no next version to test — degrades to section/tag coherence: the newest released section must carry its tag, warning when it does not (a cut may be in flight before its merge-back).
An empty `[Unreleased]` with the newest section untagged names the release in flight; with the tag present, nothing is left to release.

### Release-candidate versions

A manifest version with a pre-release suffix (`1.0.0-rc1`) declares a release candidate, and the candidate is a release: it gets the full flow below, a signed `v1.0.0-rc1` tag, and a GitHub release flagged as a pre-release.
`-rc` versions are reserved for stabilizing exactly that release: the check refuses a pre-release version whose `[Unreleased]` carries feature content (`### Added`, `### Removed`, or a `**Breaking:**` entry) — feature work resets the version to the next regular release, while `### Fixed` and `### Security` entries iterate `rc2`, `rc3`, ….
SemVer orders `1.0.0-rc1 < 1.0.0` and the baseline scan sees pre-release tags, so the final release exceeds its candidates and its compare link starts at the last one.
Number candidates `-rc.9`, `-rc.10` (numeric identifiers) when double digits are in reach: the spec compares `rc9`/`rc10` lexically, so `rc10` would order below `rc9`.

## Cutting the release branch

Dispatch a workflow that runs `cut-release` on the default branch.
It rewrites `[Unreleased]` into `[X.Y.Z] - <date>` for the version Cargo.toml declares, pushes that as `release/vX.Y.Z`, opens the merge-back pull request, and dispatches the release pipeline on the branch — explicitly, because pushes made with the workflow token trigger no workflows.
The cut refuses an empty `[Unreleased]` section and an existing release branch.

```yaml
name: Cut release
on:
  workflow_dispatch:
permissions:
  contents: write        # push the release branch
  pull-requests: write   # open the merge-back pull request
  actions: write         # dispatch the release pipeline
jobs:
  cut:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # the changelog baseline and the merge-back need history and tags
      - uses: gronke/rust-ci/.github/actions/install-toolchain@v1
      - uses: gronke/rust-ci/.github/actions/cut-release@v1
```

## The candidate loop

Every push to `release/vX.Y.Z` runs the pipeline's candidate path: the readiness gate, the build, a create-or-refresh of the `vX.Y.Z` draft pre-release, an annotated (unsigned) `vX.Y.Z-rcN` marker tag on the built commit — carrying `release-notes.md` as its message, or a bare candidate label when there is none — and the guidance summary for the release manager.
Fixes land as ordinary pushes to the branch; rc2, rc3, … refresh the same draft.
Marker tags append one `-rcN` to the version's tag name — including on a release-candidate version, where `v1.0.0-rc1-rc2` marks the second build of the `1.0.0-rc1` release.

## Signing: the sign-tags mode

Whether a human seals the release is a mode, resolved by the `promote-release` step at the end of every candidate build:

- **`manual`** — the pipeline stops at the guidance summary and the release manager signs and pushes the final tag (the runbook above).
  The signature binds the release's provenance to a human key that GitHub verifies; this is the mode for anything other people consume.
- **`off`** — the pipeline promotes the candidate itself: an annotated, unsigned final tag on the built commit carrying the marker's message, the draft published, and optionally the moving major advanced — one job, no ceremony.
  Provenance then rests on whoever holds the workflow token.
- **Unconfigured** — the repository's own enforcement decides: an active signature-requiring tag ruleset resolves to `manual`, none resolves to `off`, and unreadable rulesets resolve to `manual` (never push an unsigned tag on a repository whose policy is unknown).

Repositories that enforce signed tags apply the shipped ruleset files, so the enforcement and the detection agree:

```sh
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-signed.json
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-maintainer-only.json
```

(Or Settings → Rules → Rulesets → New ruleset → Import a ruleset.)
Both exclude the `v*-rc*` markers and the bare moving majors, and the maintainer rule carries a Repository-admin bypass for the final signed push.

## What to do with the draft pre-release

The `release-guidance` step writes these answers into every candidate build's step summary; this is the same content in prose.

### Accept — seal and publish

Whoever holds a release-signing key registered with their GitHub account:

```sh
git fetch origin 'refs/tags/vX.Y.Z-rc*:refs/tags/vX.Y.Z-rc*'
git tag -s -F <(git tag -l --format='%(contents)' vX.Y.Z-rcN) vX.Y.Z vX.Y.Z-rcN^{commit}
git push origin vX.Y.Z
```

The tag must be annotated, signed with a key GitHub can verify, and carry exactly the content the newest marker sealed — the pipeline compares trees, so the marker's commit and a rebase-merged merge-back's tip (the identical patch under a new SHA) are both valid targets.
On a rebase-only repository, merge the merge-back first and sign the rebased tip: the tag then lives on the default branch instead of an orphaned release commit.
Its message is copied from the marker (your `release-notes.md`, when you produced one), so there is nothing to retype; the `release-guidance` step prints this command with the newest `rcN` filled in.
Push the tag by name; never `git push --tags`, which pushes every local tag along.
A repository tagging script can still override the message via the guidance step's `tag-script` input.

### Reject — nothing to unwind

Delete the draft release and the release branch; the marker tags reserve nothing and can stay or be deleted.
Or push a fix to the release branch instead: the next build refreshes the same draft as the following candidate.
A rejected version number is only consumed if the draft was published — an unpublished draft's name is free to reuse on the next cut.

### What the tag push triggers

The pipeline's final path runs the signature gate, asserts the tag carries the newest marker's tree, attests and signs the assets where the repository is public, and the publish job flips the draft live.
After publication: registry publishing (`cargo publish`) stays a manual, deliberate step; promote the pre-release flag and merge the merge-back pull request per your process.

## The reference pipeline

The consumer-specific parts are marked as slots: what you build into the draft (SBOMs, binaries, provenance) and any extra gates (license sweeps, policy checks) are yours.

```yaml
name: Release
on:
  push:
    branches: ["release/v**"]
    tags: ["v*"]
  workflow_dispatch: # cut-release dispatches the first run explicitly

permissions:
  contents: write

jobs:
  gate:
    name: release readiness gate
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.expect.outputs.version }}
    steps:
      - uses: actions/checkout@v7
      - name: Derive the expected version from the ref
        id: expect
        run: |
          set -euo pipefail
          # A v* tag keeps its full version. A release-candidate manifest
          # (1.0.0-rc1) is a first-class release whose final tag is v1.0.0-rc1 —
          # not a marker to strip. Only human-pushed final tags reach the pipeline;
          # workflow-token marker pushes trigger nothing.
          case "${GITHUB_REF_TYPE}:${GITHUB_REF_NAME}" in
            branch:release/v*) version="${GITHUB_REF_NAME#release/v}" ;;
            tag:v*)            version="${GITHUB_REF_NAME#v}" ;;
            *)                 version="" ;;
          esac
          echo "version=${version}" >> "$GITHUB_OUTPUT"
      - name: Require a verified signed tag (final path only)
        if: github.ref_type == 'tag'
        uses: gronke/rust-ci/.github/actions/require-signed-tag@v1
      - uses: gronke/rust-ci/.github/actions/install-toolchain@v1
      - uses: gronke/rust-ci/.github/actions/check-release-readiness@v1
        with:
          expected-version: ${{ steps.expect.outputs.version }}
      # SLOT: extra gates (license sweep, policy checks) run here.

  draft:
    name: build the draft pre-release (candidate path)
    needs: gate
    # Only release branches build candidates: a workflow_dispatch from any other
    # branch derives no version and must not create a draft.
    if: github.ref_type == 'branch' && startsWith(github.ref_name, 'release/v')
    runs-on: ubuntu-latest
    env:
      VERSION: ${{ needs.gate.outputs.version }}
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v7

      # Notes render (Keep a Changelog), draft create/refresh, marker push — one
      # step. The title leads the message so the signed tag's subject is the
      # version. A repository with another notes format keeps the expanded steps
      # this action grew from (the changelog action's `notes` mode shows the
      # rendering contract).
      - uses: gronke/rust-ci/.github/actions/draft-release@v1
        id: draft
        with:
          version: ${{ env.VERSION }}

      # SLOT: build the release assets (SBOMs, binaries, …) into ./dist and
      # attach them to the draft. A library / publish = false crate produces
      # none, so guard the glob — an unguarded dist/* fails when empty.
      - name: Upload build assets
        run: |
          set -euo pipefail
          if compgen -G 'dist/*' >/dev/null; then
            gh release upload "v${VERSION}" dist/* --clobber
          fi

      - uses: gronke/rust-ci/.github/actions/release-guidance@v1
        with:
          version: ${{ env.VERSION }}
          marker-tag: ${{ steps.draft.outputs.marker }}
          commit: ${{ github.sha }}
          draft-url: ${{ steps.draft.outputs.url }}

      # sign-tags governs what happens next: an active signature-requiring tag
      # ruleset (or `sign-tags: manual`) defers to the release manager and the
      # guidance above; without one the pipeline promotes the candidate itself —
      # unsigned final tag with the marker's message, draft published, one job.
      - uses: gronke/rust-ci/.github/actions/promote-release@v1
        with:
          version: ${{ env.VERSION }}
          marker-tag: ${{ steps.draft.outputs.marker }}
          # sign-tags: manual        # explicit; empty auto-detects from the rulesets
          # moving-major: "true"     # advance v<MAJOR> on an off-mode promotion

  publish:
    name: publish the release (final path)
    needs: gate
    # Any tag reaching the pipeline is a human-pushed final tag: marker tags are
    # pushed with the workflow token and trigger nothing, and require-signed-tag
    # rejects unsigned tags. A first-class rc-manifest release (v1.0.0-rc1)
    # publishes here too.
    if: github.ref_type == 'tag'
    runs-on: ubuntu-latest
    environment: release # add required reviewers here for a human pause
    steps:
      - uses: actions/checkout@v7
      # SLOT: attest / sign the draft's assets (only meaningful on a public repository).

      # Tree seal against the newest marker, the draft flip (a stable version
      # sheds the pre-release flag), and the moving major advancing to the
      # highest stable release in its line — one step. Drop `moving-major` to
      # keep re-tagging a manual, signed act.
      - uses: gronke/rust-ci/.github/actions/publish-draft-release@v1
        with:
          version: ${{ needs.gate.outputs.version }}
          moving-major: "true"
```

## Repository configuration the flow relies on

- **Actions may create pull requests** (Settings → Actions → General) — `cut-release` opens the merge-back pull request with the workflow token; without the setting the cut fails at that step.
- **Tag ruleset**: let Actions create `v*-rc*` marker tags; keep final `v*` tags restricted to release managers and — to back the workflow's signature preference with real enforcement — require signatures.
  The shipped [`tags-signed.json`](../.github/rulesets/tags-signed.json) and [`tags-maintainer-only.json`](../.github/rulesets/tags-maintainer-only.json) carry exactly this shape.
  The markers are pushed unsigned with the workflow token, so a rule covering all tags blocks the candidate loop: exclude `v*-rc*` from every creation-restricting and signature-requiring tag rule, and give the release managers a bypass on the final `v*` restriction so the signed tag can be pushed at all.
  The optional moving-major step force-moves a bare `v<MAJOR>` tag unsigned, so automating it means excluding those names too; without the step, re-tagging the major stays a manual, signed act.
  `require-signed-tag` warns when the workflow enforces signatures but no active tag ruleset does.
- **Branch ruleset**: restrict `release/v*` creation and pushes to release managers and Actions.
- **A `release` environment** on the publish job; add required reviewers where a human pause before publication is wanted.
- The merge-back pull request's CI needs one "Approve and run" click when the cut ran with the workflow token: workflows do not start on pull requests authored by `github-actions`.
  A machine-user or App identity (the `cut-release` `token` and `git-user-*` inputs) removes that click.

## When a gate refuses

- *Lightweight tag* or *not a verified signed tag* — recreate the tag annotated (`git tag -s`) with a key your GitHub account knows, and force-push it by name.
- *The tag does not carry the content the last build sealed* — the branch moved after the candidate you meant to seal, or the merge-back rebase brought other changes along; re-tag the newest marker commit (or a tree-identical tip), or push the branch and let a new candidate build first.
- *Expected version != Cargo.toml version* — the ref name, the crate version, and the changelog section must agree; fix the branch content.
- *already published on crates.io* / *a published release exists* — immutable names cannot be reused, not even after deleting the release; bump the version and cut again.
- *GH013 / Cannot create ref on the marker push* — a tag ruleset restricts `v*-rc*`: the markers are pushed unsigned with the workflow token, so exclude `v*-rc*` from every creation-restricting and signature-requiring tag rule (the final `v*` rules stay).
  `require-signed-tag`'s ruleset warning covers the final tag's signature rule, not the markers.
- *The cut refuses* — `[Unreleased]` is empty, or the release branch already exists.
- *feature content on a pre-release version* — the changelog check found `### Added`, `### Removed`, or `**Breaking:**` while Cargo.toml declares `-rcN`; move the version to the next regular release.
