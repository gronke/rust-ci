# require-signed-tag

Gate a release pipeline on a verified signed tag: the ref must be an annotated tag object whose signature GitHub verifies.
Run it first in the tag run's gate job of the signed-tag flow, ahead of [`check-release-readiness`](../check-release-readiness/README.md).

## Usage

```yaml
- name: Require a verified signed tag (final path only)
  if: github.ref_type == 'tag'
  uses: gronke/rust-ci/.github/actions/require-signed-tag@v1
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `tag` | `""` | The tag to verify (defaults to the pushed tag when the ref is `refs/tags/*`). |
| `warn-only` | `"false"` | Emit a warning instead of failing when the tag is lightweight or unverified. |
| `check-ruleset` | `"true"` | When enforcing, warn if no active tag ruleset requires signatures on the tag. Skipped quietly when the token cannot read the rulesets. |
| `token` | `${{ github.token }}` | Token for the API reads. |

## Outputs

| Output | Description |
| --- | --- |
| `verified` | `"true"` when the tag is annotated and GitHub verifies its signature. |
| `commit` | The commit the tag points at. |
| `reason` | GitHub's verification reason (e.g. `valid`). |

## Notes

- The verification is GitHub's own, read through the API: no keyring on the runner, and a signature from a key the pushing account has not registered fails.
- Lightweight tags are refused.
- A non-tag ref without a `tag` input is a wiring error and fails regardless of `warn-only`.
- The gate refuses builds; only a repository tag ruleset with required signatures prevents an unsigned tag from existing, which is what the ruleset warning is about.
- A rule scoped elsewhere (e.g. to `v*-sig` companions) does not cover the release tag.
