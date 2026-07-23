# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com); releases are cut from the `[Unreleased]` section by this repository's own `changelog` action — the flow dogfoods itself.

## [Unreleased]

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

[Unreleased]: https://github.com/gronke/rust-ci/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/gronke/rust-ci/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/gronke/rust-ci/compare/v0.0.5...v1.0.0
[0.0.5]: https://github.com/gronke/rust-ci/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/gronke/rust-ci/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/gronke/rust-ci/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/gronke/rust-ci/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/gronke/rust-ci/releases/tag/v0.0.1
