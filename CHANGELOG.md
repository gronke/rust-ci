# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com); releases are cut from the `[Unreleased]` section by this repository's own `changelog` action — the flow dogfoods itself.

## [Unreleased]

### Added

- publish-draft-release gained `seal-only`, which verifies the seal and stops, so a release pipeline can gate on the content match before building artifacts — a mis-pointed tag fails in seconds instead of after every binary. `tag-sha` names the tagged commit when the run's own GITHUB_SHA is not it (a `release` event).
- check-release-readiness gained `verify`: `"false"` packages with `--no-verify`, skipping the verify build the test suite already performed while keeping the packaging, coherence and not-already-published checks.
- cargo-publish: publish the crate to crates.io, or rehearse it — `publish` defaults to `"false"`, which runs `cargo publish --dry-run` and reads no credential, so the step is safe anywhere in a pipeline. Only releases matching `tag-pattern` are published — the default admits stable `vX.Y.Z` only, so a prerelease or a bare major skips with a notice; the dry run is exempt, so a candidate still rehearses packaging in full. An upload resolves its token from `rust-lang/crates-io-auth-action` (crates.io Trusted Publishing, no stored secret) or the `registry-token` input and refuses without one; already-published is decided before the credential, so a duplicate fails in one line — and with `allow-already-published` a re-run skips with a notice and needs no token at all
- draft-release and publish-draft-release: the candidate and publish halves of the pipeline as single steps — notes render + draft create/refresh + marker push, and tree seal + draft flip + moving major. The reference pipeline and the dogfooded release.yml shrink to job scaffolding around them. Markers are discovered as the highest `rcN` in one refs listing, so a deleted middle candidate neither confuses the seal nor renumbers the next draft.
- promote-release: candidate promotion governed by `sign-tags` — `manual` defers to the release manager (implied by an active signature-requiring tag ruleset, and by unreadable rulesets), `off` lets the pipeline tag with the marker's message, publish the draft, and advance the moving major in one job.
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

[Unreleased]: https://github.com/gronke/rust-ci/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/gronke/rust-ci/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/gronke/rust-ci/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/gronke/rust-ci/compare/v0.0.5...v1.0.0
[0.0.5]: https://github.com/gronke/rust-ci/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/gronke/rust-ci/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/gronke/rust-ci/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/gronke/rust-ci/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/gronke/rust-ci/releases/tag/v0.0.1
