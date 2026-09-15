# check-release-readiness

Verify that a release is coherent before anything is built: the tag matches the declared version, and a publishable crate packages with `cargo publish --dry-run` and is not yet on crates.io.
Run it in the gate job of the release pipeline, ahead of [`publish-draft-release`](../publish-draft-release/README.md) and [`cargo-publish`](../cargo-publish/README.md).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/install-toolchain@v1
- uses: gronke/rust-ci/.github/actions/check-release-readiness@v1
  with:
    expected-version: ${{ steps.expect.outputs.version }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `package` | `""` | Package name to check (required for a workspace with more than one member). |
| `version` | `""` | The declared version, overriding Cargo.toml resolution, for a repository without a crate. Skips the crates.io checks. |
| `working-directory` | `.` | Directory containing the crate or workspace. |
| `expected-version` | `""` | Version the crate must declare. Defaults to the pushed tag on a `refs/tags/v*` ref (leading `v` stripped); empty on a non-tag ref skips the coherence check. |
| `changelog` | `CHANGELOG.md` | Changelog whose newest released section declares the version when there is no Cargo.toml and no `version` input, relative to the working directory. |
| `verify` | `"true"` | `"false"` adds `--no-verify` to the dry run, skipping the verify build. |
| `run-tests` | `"false"` | Also run `cargo test --workspace`. |

## Notes

- The version ladder is the `version` input, else Cargo.toml through `cargo metadata`, else the changelog's newest released section.
- Crates with `publish = false`, and repositories without a crate, get the coherence check only.
- The crates.io probe is unauthenticated; an inconclusive HTTP status is a warning, not a failure.
- `run-tests` is skipped with a notice when there is no Cargo.toml.
