# cargo-publish

Publish the crate to crates.io, or rehearse the publish with `cargo publish --dry-run`.
Run it last in the release pipeline, behind [`require-signed-release`](../require-signed-release/README.md) or another human gate; the GitHub Release is published by [`publish-draft-release`](../publish-draft-release/README.md).

## Usage

```yaml
permissions:
  id-token: write   # crates.io Trusted Publishing
steps:
  - id: auth
    uses: rust-lang/crates-io-auth-action@v1
  - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
    with:
      publish: "true"
      registry-token: ${{ steps.auth.outputs.token }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `publish` | `"false"` | `"true"` uploads to crates.io. Anything else runs `cargo publish --dry-run` and touches no credential. |
| `tag-pattern` | `^v[0-9]+\.[0-9]+\.[0-9]+$` | Extended regex `v<version>` must match to be published; a non-matching version is a notice and a skip. Empty disables the check. |
| `registry-token` | `""` | crates.io API token: the `token` output of `rust-lang/crates-io-auth-action`, or a classic token from a secret. Empty falls back to a job-level `CARGO_REGISTRY_TOKEN`. |
| `package` | `""` | Workspace member to publish; empty resolves the sole package. |
| `locked` | `"true"` | Pass `--locked`, so the committed `Cargo.lock` is what gets published. |
| `allow-already-published` | `"false"` | `"true"` skips with a notice when the version is already on crates.io; otherwise the step fails. |
| `working-directory` | `.` | Directory of the checked-out repository. |

## Outputs

| Output | Description |
| --- | --- |
| `published` | `"true"` when this run uploaded to crates.io. |
| `version` | The crate version the step acted on. |
| `already-published` | `"true"` when the version was already on crates.io. |

## Notes

- A crate with `publish = false` is a notice and a skip; no input overrides the manifest.
- The default `tag-pattern` admits stable `vX.Y.Z` only, so prereleases (`v1.0.0-rc1`), build metadata (`v1.0.0+build`) and bare majors never reach the registry; the dry run is exempt from the pattern.
- The already-published probe runs before the credential is read, so an allowed re-run needs no token.
- The token reaches cargo through one call's environment and is never written to disk (no `cargo login`).
- `rust-lang/crates-io-auth-action` sets a `token` output (needs `id-token: write`) and never exports `CARGO_REGISTRY_TOKEN`; an upload is irreversible, a published version can only be yanked.
