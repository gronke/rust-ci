# Showcase: QA, test, release, publish

One repository, four workflows, every step an action from this repository.
The per-action READMEs carry the inputs; this page shows how the pieces line up.

## Pull requests: QA and test

Native runners: `install-toolchain`, `rust-cache`, `lint-and-test`, `changelog` in `check` mode, `rust-cache-save` with `save: "false"` so pull requests only read what the default branch maintains.
Sealed runners: the reusable `ci.yml` workflow, which builds the toolchain image, warms the cache with `cargo-fetch` and runs `lint-and-test-docker` under `--network=none`, plus `msrv` for the support floor.

```yaml
on: [pull_request]
jobs:
  qa:
    uses: gronke/rust-ci/.github/workflows/ci.yml@v1
  changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: gronke/rust-ci/.github/actions/changelog@v1
        with:
          mode: check
```

## Default branch: keep the caches warm

The same QA job on pushes to the default branch, with `rust-cache-save` saving, so every pull request restores a current target entry.
With a self-hosted tier, `sccache` and `crates-mirror` pick up the host's backend from the job environment and need no workflow change ([self-hosted.md](self-hosted.md)).

## Release: cut, candidate, signed tag

`cut-release` turns `[Unreleased]` into the released section, pushes the release branch, opens the merge-back pull request and dispatches the pipeline.
The pipeline gates with `check-release-readiness`, builds, then `draft-release` creates the draft pre-release and pushes an unsigned candidate marker, and `release-guidance` writes the sign-and-push commands into the step summary.
A human signs the marker's commit as the final tag and pushes it by name; `require-signed-tag` gates the tag run, `publish-draft-release` seals the tag against the newest marker, publishes the draft and advances the moving major.
[release-flow.md](release-flow.md) is the runbook, and this repository's own `release.yml` and `cut.yml` are the reference pipeline.

## Publish: crates.io behind the signature gate

`require-signed-tag` stops the tag run unless the tag is an annotated object whose signature GitHub verifies.
`cargo-publish` runs behind it and uploads only versions matching its `tag-pattern`, with the Trusted Publishing token from `rust-lang/crates-io-auth-action` passed as `registry-token`; with `publish` left at its default it rehearses with `cargo publish --dry-run`.

```yaml
permissions: { id-token: write, contents: write }
steps:
  - uses: actions/checkout@v7
  - uses: gronke/rust-ci/.github/actions/check-release-readiness@v1
  - uses: gronke/rust-ci/.github/actions/require-signed-tag@v1
  - id: auth
    uses: rust-lang/crates-io-auth-action@v1
  - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
    with:
      publish: "true"
      registry-token: ${{ steps.auth.outputs.token }}
```

## The hardened variant

- Signed tags: import `.github/rulesets/tags-maintainer-only.json` so only admins create `v*` tags; a ruleset cannot verify a tag's signature, `require-signed-tag` does.
- Sealed verify-build: `publish-dry-run` runs the publish checks without a build, then `cargo package` under `--network=none`, so dependency code executes without network at release time.
- No stored registry secret: Trusted Publishing mints a 30-minute token from the job's OIDC identity.
- Least privilege: each job declares only the permissions its steps need; the sealed jobs need `contents: read`.
- Pinned actions: pin third-party actions by commit SHA and let Dependabot propose bumps.

## Peripherals worth adding

- `actions/attest-build-provenance` for signed provenance on release assets.
- `cargo-deny` or `cargo-audit`, installed with `cargo-install` and run sealed with `cargo-use`.
- Dependabot for the action pins in `.github/workflows`.
