# The release flow

How a crate goes from `[Unreleased]` entries to a published GitHub release sealed by a signed tag, composed from the release actions in this repository:
[`changelog`](../README.md#changelog), [`cut-release`](../README.md#cut-release), [`check-release-readiness`](../README.md#check-release-readiness), [`require-signed-tag`](../README.md#require-signed-tag), and [`release-guidance`](../README.md#release-guidance).

The flow is branch-based: every push of a `release/vX.Y.Z` branch rebuilds a **draft** pre-release, and the signed `vX.Y.Z` tag publishes that draft, exactly once.
Drafts are invisible and mutable, and candidate marker tags reserve nothing, so the whole loop can run, fail, and be deleted without consequence.
Publication is the one irreversible step: a published release is immutable — assets frozen, tag locked, and the tag name permanently consumed even if the release is deleted afterwards.

## Versions come from Cargo.toml

Every stage reads the version the manifest declares (through `cargo metadata`); nothing else names a version.
The first change after a release bumps the version; later pull requests in the same window ride along without bumping again.
The `changelog` check enforces this on every pull request: while `CHANGELOG.md` carries `[Unreleased]` entries, the crate version must exceed the last released baseline by SemVer precedence, and a `**Breaking:**` entry demands more than a patch bump.

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

## What to do with the draft pre-release

The `release-guidance` step writes these answers into every candidate build's step summary; this is the same content in prose.

### Accept — seal and publish

Whoever holds a release-signing key registered with their GitHub account:

```sh
git fetch origin 'refs/tags/vX.Y.Z-rc*:refs/tags/vX.Y.Z-rc*'
git tag -s -F <(git tag -l --format='%(contents)' vX.Y.Z-rcN) vX.Y.Z vX.Y.Z-rcN^{commit}
git push origin vX.Y.Z
```

The tag must be annotated, signed with a key GitHub can verify, and point at exactly the commit the newest marker sealed — the pipeline refuses anything else.
Its message is copied from the marker (your `release-notes.md`, when you produced one), so there is nothing to retype; the `release-guidance` step prints this command with the newest `rcN` filled in.
Push the tag by name; never `git push --tags`, which pushes every local tag along.
A repository tagging script can still override the message via the guidance step's `tag-script` input.

### Reject — nothing to unwind

Delete the draft release and the release branch; the marker tags reserve nothing and can stay or be deleted.
Or push a fix to the release branch instead: the next build refreshes the same draft as the following candidate.
A rejected version number is only consumed if the draft was published — an unpublished draft's name is free to reuse on the next cut.

### What the tag push triggers

The pipeline's final path runs the signature gate, asserts the tag seals the newest marker commit, attests and signs the assets where the repository is public, and the publish job flips the draft live.
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
      # SLOT: produce release-notes.md — the draft body and the marker/tag message.
      # Optional: without it the draft gets a minimal note and the marker a bare
      # candidate label. A Keep a Changelog file renders with the changelog action:
      #   - uses: gronke/rust-ci/.github/actions/changelog@v1
      #     with: { mode: notes, version: ${{ env.VERSION }}, title: v${{ env.VERSION }} }
      # The title leads the message so the signed tag's subject is the version, not
      # the section's first group heading. Other formats write release-notes.md any way.
      # SLOT: build the release assets (SBOMs, binaries, …) into ./dist.
      - name: Create or refresh the draft pre-release
        run: |
          set -euo pipefail
          notes=(--notes "Release v${VERSION}.")
          [ -s release-notes.md ] && notes=(--notes-file release-notes.md)
          if gh release view "v${VERSION}" >/dev/null 2>&1; then
            gh release edit "v${VERSION}" "${notes[@]}"
          else
            gh release create "v${VERSION}" --draft --prerelease --title "v${VERSION}" "${notes[@]}"
          fi
          # SLOT: upload build assets, if any. A library / publish = false crate
          # produces none, so guard the glob — an unguarded dist/* fails when empty.
          if compgen -G 'dist/*' >/dev/null; then
            gh release upload "v${VERSION}" dist/* --clobber
          fi
      - name: Advance the candidate marker tag
        id: marker
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          n=1
          while gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/v${VERSION}-rc${n}" >/dev/null 2>&1; do
            n=$((n + 1))
          done
          # The marker's message is release-notes.md when present (so promoting a
          # candidate copies it into the signed tag), else a bare candidate label.
          if [ -s release-notes.md ]; then
            git tag -a -F release-notes.md "v${VERSION}-rc${n}" "${GITHUB_SHA}"
          else
            git tag -a -m "v${VERSION} candidate ${n}" "v${VERSION}-rc${n}" "${GITHUB_SHA}"
          fi
          git push origin "refs/tags/v${VERSION}-rc${n}" || {
            echo "::error::the marker push was rejected (GH013) — the tag ruleset must let Actions create unsigned v*-rc* markers: exclude v*-rc* from creation-restricting and signature-requiring tag rules. See “Repository configuration the flow relies on”."
            exit 1
          }
          echo "marker=v${VERSION}-rc${n}" >> "$GITHUB_OUTPUT"
      - uses: gronke/rust-ci/.github/actions/release-guidance@v1
        with:
          version: ${{ env.VERSION }}
          marker-tag: ${{ steps.marker.outputs.marker }}
          commit: ${{ github.sha }}

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
    env:
      VERSION: ${{ needs.gate.outputs.version }}
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v7
      - name: The tag must seal the newest candidate marker
        run: |
          set -euo pipefail
          n=1
          while gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/v${VERSION}-rc$((n + 1))" >/dev/null 2>&1; do
            n=$((n + 1))
          done
          marker_commit="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/v${VERSION}-rc${n}" --jq '.object.sha')"
          marker_commit="$(gh api "repos/${GITHUB_REPOSITORY}/git/tags/${marker_commit}" --jq '.object.sha' 2>/dev/null || printf '%s' "$marker_commit")"
          if [ "$marker_commit" != "$GITHUB_SHA" ]; then
            echo "::error::v${VERSION} points at ${GITHUB_SHA} but the last build (v${VERSION}-rc${n}) is ${marker_commit}"
            exit 1
          fi
      # SLOT: attest / sign the draft's assets (only meaningful on a public repository).
      - name: Publish
        run: gh release edit "v${VERSION}" --draft=false

      # OPTIONAL: maintain a moving v<MAJOR> tag on the latest release, for
      # consumers who pin the major (actions, not crates). Skips prereleases.
      # Drop the step to keep re-tagging a manual, signed act.
      - name: Advance the moving major tag
        run: |
          set -euo pipefail
          case "$VERSION" in *-*) echo "prerelease; the moving major stays"; exit 0 ;; esac
          MAJOR="v${VERSION%%.*}"
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git tag -f -a -m "${MAJOR} (moving major) -> v${VERSION}" "${MAJOR}" "${GITHUB_SHA}"
          git push -f origin "refs/tags/${MAJOR}"
```

## Repository configuration the flow relies on

- **Actions may create pull requests** (Settings → Actions → General) — `cut-release` opens the merge-back pull request with the workflow token; without the setting the cut fails at that step.
- **Tag ruleset**: let Actions create `v*-rc*` marker tags; keep final `v*` tags restricted to release managers and — to back the workflow's signature preference with real enforcement — require signatures.
  The markers are pushed unsigned with the workflow token, so a rule covering all tags blocks the candidate loop: exclude `v*-rc*` from every creation-restricting and signature-requiring tag rule, and give the release managers a bypass on the final `v*` restriction so the signed tag can be pushed at all.
  The optional moving-major step force-moves a bare `v<MAJOR>` tag unsigned, so automating it means excluding those names too; without the step, re-tagging the major stays a manual, signed act.
  `require-signed-tag` warns when the workflow enforces signatures but no active tag ruleset does.
- **Branch ruleset**: restrict `release/v*` creation and pushes to release managers and Actions.
- **A `release` environment** on the publish job; add required reviewers where a human pause before publication is wanted.
- The merge-back pull request's CI needs one "Approve and run" click when the cut ran with the workflow token: workflows do not start on pull requests authored by `github-actions`.
  A machine-user or App identity (the `cut-release` `token` and `git-user-*` inputs) removes that click.

## When a gate refuses

- *Lightweight tag* or *not a verified signed tag* — recreate the tag annotated (`git tag -s`) with a key your GitHub account knows, and force-push it by name.
- *The tag points at X but the last build is Y* — the branch moved after the candidate you meant to seal; re-tag the newest marker commit, or push the branch and let a new candidate build first.
- *Expected version != Cargo.toml version* — the ref name, the crate version, and the changelog section must agree; fix the branch content.
- *already published on crates.io* / *a published release exists* — immutable names cannot be reused, not even after deleting the release; bump the version and cut again.
- *GH013 / Cannot create ref on the marker push* — a tag ruleset restricts `v*-rc*`: the markers are pushed unsigned with the workflow token, so exclude `v*-rc*` from every creation-restricting and signature-requiring tag rule (the final `v*` rules stay).
  `require-signed-tag`'s ruleset warning covers the final tag's signature rule, not the markers.
- *The cut refuses* — `[Unreleased]` is empty, or the release branch already exists.
- *feature content on a pre-release version* — the changelog check found `### Added`, `### Removed`, or `**Breaking:**` while Cargo.toml declares `-rcN`; move the version to the next regular release.
