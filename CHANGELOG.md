# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com); releases are cut from the `[Unreleased]` section by this repository's own `changelog` action — the flow dogfoods itself.

## [1.5.0] - 2026-08-03

### Added

- route-git-token: route git fetches on the runner through a short-lived token — the unsealed sibling of `cargo-fetch`'s `git-token`, for jobs that run plain `cargo build` or `git clone` outside the sealed container. The rewrite is exported as `GIT_CONFIG_*` entries through `$GITHUB_ENV` rather than written to a gitconfig file, so it dies with the job, and invocations append rather than clobber: two tokens for two owners coexist. `CARGO_NET_GIT_FETCH_WITH_CLI` comes along, since cargo's libgit2 path ignores git's rewrites. The defaults speak GitHub, and `host`, `username` and `path` cover any authenticated https host. Every input that reaches a gitconfig key is charset-validated first, the token included: it is embedded in a `$GITHUB_ENV` line, where a newline would export an environment variable of its own to every later step and escape the log mask.

### Changed

- docs/release-flow.md describes how a cargo workspace releases: `package:` names the crate whose version is the release version, `cargo metadata` resolves `version.workspace = true` inheritance so one unified workspace version works, and per-crate tags with independently versioned members stay out of scope.

## [1.4.2] - 2026-08-02

### Fixed

- rust-cache-save: a cache directory that is not a cargo workspace is saved unpruned instead of failing. The prune step is driven by `cargo metadata`, so it died before the save on any other cache family — a C++ build tree such as pdfium's `out/`, where the directory itself is the value and there is no dependency graph to prune against. The working directory is checked for a `Cargo.toml` first, in the same place `cargo metadata` would have run.
- release-flow: the dogfooded pipeline guards its gate against the moving major, as the reference pipeline already did. The pipeline pushes `v1` with the workflow token, which fires no events, but a maintainer moving it by hand does — and the gate then derived the version "1" from the ref and refused the repository's own major tag.

### Changed

- docs/release-flow.md: publishing before the merge-back lands is named for what it costs. The tag is created on a default branch that does not yet carry the release commit, so it names a version its own changelog does not declare; the gate refuses, the moving major never advances, and immutable releases freeze that tag for good. Nothing downstream runs, but the version is spent and the release has to be cut again under a new number.

## [1.4.1] - 2026-08-02

### Added

- retry-transient: a shared helper that retries a command whose failure came from the network rather than from the work it was asked to do, bounded by `RETRY_ATTEMPTS`, with the pause tripling from `RETRY_DELAY` and holding at `RETRY_MAX_DELAY`.
- require-signed-release gained `attestation-tag` and `require-published`, so the signature-triggered shape the guide documents needs no shell of its own: a job passes the pushed companion instead of a version, and the release it seals is derived by commit identity — any naming convention works, and a commit carrying no published release, or more than one, is refused rather than guessed. `release-tag` and `version` join the outputs, and `require-published` turns a draft into an error rather than an unsigned answer, since a signature completes automation and never publishes drafts.

### Fixed

- build-image survives a registry hiccup: the base image comes from Docker Hub, which times out and rate-limits for reasons that have nothing to do with the build, and a single `i/o timeout` there used to fail the job. Both build paths now retry such a failure on a budget that rides out a degraded registry rather than a momentary blip: five attempts, the pause tripling from five seconds and holding at sixty, about two minutes in all. A build that fails on its own terms — a bad Dockerfile, a compile error — still fails on its first attempt and keeps its exit status.

## [1.4.0] - 2026-08-01

### Added

- require-signed-release: gate registry publication on a human signature, whichever go-live mode the repository runs. Three sources, checked in order: a verified-signed release tag, another verified-signed tag on the same commit (the attestation companion, narrowed with `attestation-tags`), or — opt-in, with GitHub's web-flow key excluded by default — a verified commit signature. Unsigned is an answer, not a failure: feed `signed` into cargo-publish's `publish` input and an unsigned release rehearses instead of uploading; a signed companion pushed later, retroactively included, completes the publication.
- release-guidance gained `go-live`: "publish-draft" renders merge-then-publish — the admin publishing the draft creates the tag and is the flow's one human gate — plus the optional signed `vX.Y.Z-sig` attestation companion; "signed-tag" (the default) is the runbook as before. In publish-draft mode the step errors at candidate time when an active tag ruleset still requires signatures on the version itself, so CI never sets up a tag the repository's own policy rejects.

### Changed

- tag-rulesets: the signature probe is pattern-aware — `signature_rule_covers_ref` answers for one concrete ref, so a rule scoped to `v*-sig` companions does not mark plain versions as signature-enforced, and require-signed-tag's alignment warning asks about the very tag it gates. The verdict is unknown whenever the policy cannot be established: an unreadable listing or ruleset detail, and any condition pattern the probe cannot faithfully evaluate — a rule that might cover the ref must never read as absent. The rulesets are read once per process, so asking twice costs nothing.
- promote-release: sign-tags autodetection asks whether a signature rule covers the final tag, and an explicit `off` colliding with such a rule errors before anything is created — CI never pushes an unsigned tag the repository's own policy rejects, or one a bypass would let fail the gate after going live. Re-running a completed promotion skips the tag push and proceeds to the idempotent flip and major; the same version on a different commit is a named conflict.
- This repository releases itself in the publish-go-live mode: the gate drops `require-signed-tag`, the candidate run drops `promote-release` and renders the publish-draft runbook, and the admin publishing the draft creates the tag and is the one human gate. The draft's target is pinned to the merged commit, so the tag is created on exactly the content the marker sealed and the seal passes by construction. docs/release-flow.md describes the mode, the `vX.Y.Z-sig` attestation companion and the retargeted ruleset, and gains a table for choosing between the three go-live modes; the signed flow stays the reference default and keeps the line about never hand-publishing its drafts.
- README and docs/release-flow.md state the tier contract: every action is a base operation composed under the consumer's own conditions, only the six changelog-flow actions assume Keep-a-Changelog and candidate markers, and the registry ending — readiness, the signature gate, cargo-publish — bolts onto any pipeline, changelog-free.

## [1.3.0] - 2026-08-01

### Added

- publish-draft-release gained `seal-only`, which verifies the seal and stops, so a release pipeline can gate on the content match before building artifacts — a mis-pointed tag fails in seconds instead of after every binary. `tag-sha` names the tagged commit when the run's own GITHUB_SHA is not it (a `release` event).
- check-release-readiness gained `verify`: `"false"` packages with `--no-verify`, skipping the verify build the test suite already performed while keeping the packaging, coherence and not-already-published checks.
- cargo-publish: publish the crate to crates.io, or rehearse it — `publish` defaults to `"false"`, which runs `cargo publish --dry-run` and reads no credential, so the step is safe anywhere in a pipeline. Only releases matching `tag-pattern` are published — the default admits stable `vX.Y.Z` only, so a prerelease or a bare major skips with a notice; the dry run is exempt, so a candidate still rehearses packaging in full. An upload resolves its token from `rust-lang/crates-io-auth-action` (crates.io Trusted Publishing, no stored secret) or the `registry-token` input and refuses without one; already-published is decided before the credential, so a duplicate fails in one line — and with `allow-already-published` a re-run skips with a notice and needs no token at all
- draft-release and publish-draft-release: the candidate and publish halves of the pipeline as single steps — notes render + draft create/refresh + marker push, and tree seal + draft flip + moving major. The reference pipeline and the dogfooded release.yml shrink to job scaffolding around them. Markers are discovered as the highest `rcN` in one refs listing, so a deleted middle candidate neither confuses the seal nor renumbers the next draft.
- promote-release: candidate promotion governed by `sign-tags` — `manual` defers to the release manager (implied by an active signature-requiring tag ruleset, and by unreadable rulesets), `off` lets the pipeline tag with the marker's message, publish the draft, and advance the moving major in one job. A stable promotion sheds the draft's pre-release flag, and the major advances only for the highest stable in its line — decided before anything goes live, so a backport publishes without touching it.
- Importable tag rulesets under `.github/rulesets/` — `tags-signed.json` and `tags-maintainer-only.json` carry the marker and moving-major exclusions the flow relies on.
- docs/release-flow.md: the release manager's runbook — the signed path start to finish, with the recovery moves for rejected markers and refused seals.

### Changed

- The moving major advances to the highest stable release in its line and only onto a commit reachable from the default branch — publishing a backport patch no longer rewinds it. A stable version's publish also drops the draft's pre-release flag. The move is resolved and validated before the draft flips live, so a refusal leaves the release a draft.
- release-flow: the publish gate seals the tag against the newest marker's tree, not its commit — a rebase-merged merge-back rewrites the SHA but carries the identical content, so on rebase-only repositories the merge-back lands first and the signed tag points at the rebased tip.

## [1.2.0] - 2026-07-23

### Added

- changelog: a `notes` mode renders a released section as plain text — inline Markdown stripped, an optional `title` leading so a git tag's subject is the version — for a tag message or release body; `release-guidance`'s accept command copies the marker's message into the signed tag.
- The version resolves without Cargo.toml: `cut-release` and `check-release-readiness` gain a `version` input, `notes` falls back to the changelog's newest released section, and `check` without any version degrades to section/tag coherence — a repository whose only manifest is its changelog can release itself.
- release-flow: an optional moving-major step after publish advances a bare `v<MAJOR>` tag to the latest release; prereleases skip, and re-tagging stays a manual signed act without the step.

### Changed

- release-flow: only release branches build candidates — a `workflow_dispatch` from any other branch derives no version and creates no draft.
- release-flow: the marker step names the fix when a tag ruleset rejects the push (GH013), instead of dying on raw git output.

## [1.1.0] - 2026-07-20

### Added

- changelog: SemVer-precedence baselines are rc-aware, and `-rc` versions accept only stabilization content.
- cut-release: changelog cut, release branch, merge-back pull request, and pipeline dispatch in one action.
- require-signed-tag: a GitHub-verified signed-tag gate with a warn-only mode and a tag-ruleset alignment warning.
- release-guidance: the release manager's accept/reject/next steps in the run's step summary.
- docs/release-flow.md: the branch-based flow, the reference workflows, and rc-manifest releases.

### Fixed

- msrv: the resolve copy survives a concurrent repack of `.git`.

## [1.0.0] - 2026-07-18

### Added

- build-image: a `targets` input bakes cross-compile targets into the image, so cargo-docker can `check --target`.
- A reusable `.github/workflows/ci.yml` (`workflow_call`): the sealed pipeline — build-image, cargo-fetch, lint-and-test-docker, cross-target check, msrv — in one call. The interface is stable; consumers pin `@v1`.

## [0.0.5] - 2026-07-12

### Added

- changelog: check version bumps and breaking changes, or cut a release section from CHANGELOG.md and export `CHANGELOG_VERSION`.
- cargo-out-dir: build a package and expose its exact build-script `OUT_DIR`; cargo-docker resolves the same `OUT_DIR` as a translated host path, and both replay compiler diagnostics from cargo's JSON stream.
- rust-cache-save: split cargo caching by churn — rust-cache restores the registry and optional target, the save action prunes `target/` to dependency artifacts and saves under the exact restore key; exact hits skip prune and save.

### Changed

- rust-cache honors `CARGO_HOME` and supports restore-only registry caching with `save: "false"`.
- actions/cache moved from v5 to v6; cache inventory and cleanup are documented.

## [0.0.4] - 2026-07-03

### Added

- msrv: build the crate on its declared MSRV, with the image built at that toolchain.

### Fixed

- msrv: the lockfile resolves up front, in a disposable copy of the source.

## [0.0.3] - 2026-06-27

### Changed

- build-image: the CI image builds locally instead of pulling from GHCR.

## [0.0.2] - 2026-06-26

### Added

- cargo-install and cargo-use: sealed cargo-tool install and run.
- cargo-docker and publish-dry-run: the sealed Docker pattern, hardened.
- Per-action READMEs and Marketplace blurbs; an npm-utils consumer example.

## [0.0.1] - 2026-06-25

### Added

- First release — reusable Rust CI/CD actions (bring-up baseline).

[1.3.0]: https://github.com/gronke/rust-ci/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/gronke/rust-ci/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/gronke/rust-ci/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/gronke/rust-ci/compare/v0.0.5...v1.0.0
[0.0.5]: https://github.com/gronke/rust-ci/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/gronke/rust-ci/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/gronke/rust-ci/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/gronke/rust-ci/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/gronke/rust-ci/releases/tag/v0.0.1
