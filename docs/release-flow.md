# The release flow

How a repository goes from `[Unreleased]` changelog entries to a published GitHub release, and for a crate to a crates.io upload, composed from the ten release actions in this repository:
[`changelog`](../.github/actions/changelog/README.md), [`cut-release`](../.github/actions/cut-release/README.md), [`check-release-readiness`](../.github/actions/check-release-readiness/README.md), [`draft-release`](../.github/actions/draft-release/README.md), [`release-guidance`](../.github/actions/release-guidance/README.md), [`promote-release`](../.github/actions/promote-release/README.md), [`publish-draft-release`](../.github/actions/publish-draft-release/README.md), [`require-signed-tag`](../.github/actions/require-signed-tag/README.md), [`require-signed-release`](../.github/actions/require-signed-release/README.md), and [`cargo-publish`](../.github/actions/cargo-publish/README.md).
Every gate is a step a repository can replace or drop.

The flow is branch-based: every push of a `release/vX.Y.Z` branch rebuilds a draft pre-release, and the final `vX.Y.Z` tag publishes that draft once.
Drafts are invisible and mutable, and candidate marker tags reserve nothing, so the loop can run, fail, and be deleted without consequence.
Publication is the one irreversible step: a published release is immutable and its tag name stays consumed even if the release is deleted, and a crates.io upload can only be yanked.

[`.github/workflows/release.yml`](../.github/workflows/release.yml) and [`.github/workflows/cut.yml`](../.github/workflows/cut.yml) are the reference pipeline; this repository releases itself with them in the publish-draft mode.

## Runbook

1. Cut: dispatch the cut workflow on the default branch; on a repository without a Cargo.toml, type the version into the dispatch form.
2. Candidate loop: watch the build on `release/vX.Y.Z`, which refreshes the draft pre-release and pushes a `vX.Y.Z-rcN` marker on the built commit; push fixes to the branch, and each push refreshes the same draft as the next candidate.
3. Go live per the table below; the run's step summary carries the exact commands with the marker and commit filled in.
4. Merge-back: merge the pull request the cut opened, so the default branch carries the released section.
   In the publish-draft mode this happens before publishing, always; in the signed mode it may happen first, and the rebased tip is a valid tag target.
5. Delete the release branch.

## The version ladder

`changelog`, `cut-release` and `check-release-readiness` read the version the same way: the explicit `version` input, else Cargo.toml through `cargo metadata`, else (for `check-release-readiness` and the `notes` mode) the changelog's newest released section; `cut-release` needs the input on a repository without a crate.
The candidate and go-live actions take the version as a required input, and `cargo-publish` reads it from Cargo.toml only.
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
On a tag run the signed mode adds `require-signed-tag`, and the seal-only step fails a tag that does not carry the newest marker's tree before any artifact job runs.

**Candidate** (`draft-release`, `release-guidance`, `promote-release`): every push to the release branch renders the changelog section into `release-notes.md`, creates or refreshes the `vX.Y.Z` draft pre-release, pushes an annotated unsigned `vX.Y.Z-rcN` marker on the built commit carrying the same notes as its message, and writes the release manager's next steps into the step summary.
`promote-release` then defers or promotes, as the go-live table says.

**Go-live** (`publish-draft-release`): the final `vX.Y.Z` tag arrives, and the tag run seals it against the newest marker by tree, flips the draft live (a stable version sheds the pre-release flag), and with `moving-major` advances `v<MAJOR>` to the highest stable release in its line.

**Registry** (`require-signed-release`, `cargo-publish`): the publish job uploads the crate only when a verified human signature covers the release commit; an unsigned release rehearses with `--dry-run` instead.

**Merge-back**: the pull request the cut opened lands on the default branch; on a repository without a Cargo.toml, `check` warns until the newest released section carries its tag.

## Go-live modes

| Who creates the final tag | Configuration |
| --- | --- |
| A human signs and pushes `vX.Y.Z` on the marker's commit or the rebase-merged tip (`git tag -s -F <(git tag -l --format='%(contents)' vX.Y.Z-rcN) vX.Y.Z <commit>`, then `git push origin vX.Y.Z`, never `git push --tags`); the tag push runs the final path. | `release-guidance` with `go-live: signed-tag` (the default), `promote-release` in `sign-tags: manual`, `require-signed-tag` in the gate, rulesets `tags-signed` and `tags-maintainer-only`. |
| The candidate run creates the annotated, unsigned tag with the marker's message, publishes the draft, and with `moving-major` advances the moving major in one job. | `promote-release` with `sign-tags: off`; no signature-requiring rule may cover `vX.Y.Z`. |

Left empty, `sign-tags` auto-detects: an active signature-requiring tag ruleset covering `vX.Y.Z` means `manual`, none means `off`, unreadable rulesets mean `manual`.
Publish-draft mode in one line: `release-guidance` with `go-live: publish-draft` and no `promote-release` step; the release manager merges the merge-back and then publishes the draft with `--target` pinned to the merged commit, GitHub creates the tag on that commit and the tag push runs the final path, and signatures live on an optional `vX.Y.Z-sig` companion governed by `tags-sig-signed`.

## Tag rulesets

```sh
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-signed.json
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-maintainer-only.json
# publish-draft mode: in place of tags-signed.json
gh api repos/{owner}/{repo}/rulesets --input .github/rulesets/tags-sig-signed.json
```

`tags-signed` requires signatures and `tags-maintainer-only` restricts creation, update and deletion on every tag except the `v*-rc*` markers and the bare `v<MAJOR>` tags; the maintainer rule carries a repository-admin bypass for the final push.
`tags-sig-signed` requires signatures only on `vX.Y.Z-sig` companions, so the tag GitHub creates on publish stays unsigned; an all-`v*` signature rule must be removed or retargeted first, and `release-guidance` errors at candidate time while one still covers the version.

## Registry publication behind a signature

`require-signed-release` answers whether a verified signature covers the release commit: the release tag itself, another verified-signed tag on the same commit (`vX.Y.Z-sig` by convention, narrowed with `attestation-tags`), or, opt-in, the commit signature.
Unsigned is an answer, not a failure; the job needs `id-token: write` for `rust-lang/crates-io-auth-action`, whose `token` output is the credential:

```yaml
      - id: sig
        uses: gronke/rust-ci/.github/actions/require-signed-release@v1
        with:
          version: ${{ needs.gate.outputs.version }}
          attestation-tags: "v*-sig"
      - if: steps.sig.outputs.signed == 'true'
        id: auth
        uses: rust-lang/crates-io-auth-action@v1
      - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
        with:
          publish: ${{ steps.sig.outputs.signed }}
          registry-token: ${{ steps.auth.outputs.token }}
          allow-already-published: "true"
```

The companion's push can be the trigger: a workflow on `push: tags: ["v*-sig"]` passes `attestation-tag: ${{ github.ref_name }}` and `require-published: "true"`, the release is derived by commit, and a signature pushed later for an old release completes a publication that was waiting for it.

## Repository settings the flow relies on

- Settings > Actions > General: "Allow GitHub Actions to create and approve pull requests", or `cut-release` fails at the merge-back.
- A tag ruleset that lets Actions create `v*-rc*` markers (and the bare `v<MAJOR>` tags when `moving-major` is on) and restricts final `v*` tags to release managers; the shipped files carry this shape.
- A branch ruleset restricting `release/v*` creation and pushes to release managers and Actions.
- A `release` environment on the publish job, with required reviewers where a human pause before publication is wanted; in the publish-draft mode it gates only what the pipeline runs after the click, not the publication itself.
- The merge-back pull request triggers no CI when the cut ran with the workflow token; a machine-user or App token through `cut-release`'s `token` and `git-user-*` inputs does.
- Trusted Publishing on crates.io for the publishing workflow, plus `id-token: write` on the publish job.

## When a gate refuses

| Refusal | What happened, what to do |
| --- | --- |
| lightweight tag, or not a verified signed tag | Recreate the tag annotated (`git tag -s`) with a key your GitHub account knows and force-push it by name. |
| does not carry the content the last build sealed | The branch moved after the candidate, or the merge-back rebase brought other changes; re-tag the newest marker commit (or a tree-identical tip), or push the branch and let a new candidate build. |
| tag/expected version != declared version | The ref name, the crate version and the changelog section must agree; fix the branch content. In the publish-draft mode this is publishing before the merge-back: the tag is spent under immutable releases, cut the next number. |
| already published on crates.io | A published version cannot be replaced; bump the version and cut again. |
| GH013 on the marker push | A tag ruleset restricts `v*-rc*`; exclude the markers from every creation-restricting and signature-requiring tag rule. |
| GH013 on the final tag push (`sign-tags: off`) | A ruleset restricts final `v*` tags; let Actions create them, or switch to `sign-tags: manual`. |
| an active tag ruleset requires signatures on vX.Y.Z (`sign-tags: off` or `go-live: publish-draft`) | The mode contradicts the repository's policy; retarget the rule to `v*-sig` companions or use the signed mode. |
| no candidate marker for vX.Y.Z | The tag arrived without a candidate build; cut a release branch first. |
| the cut refuses | `[Unreleased]` is empty, or the release branch already exists. |
| feature content on a pre-release version | `### Added`, `### Removed` or `**Breaking` while the version declares `-rcN`; move the version to the next regular release. |
| still a draft (`require-published`) | A signature completes automation, it does not publish drafts; publish the release first. |
