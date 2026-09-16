# require-signed-tag

The signature gate of the release pipeline: the ref must be an annotated tag object whose signature GitHub verifies.
Run it in the tag run's gate job, after [`check-release-readiness`](../check-release-readiness/README.md) and before the seal-only step of [`publish-draft-release`](../publish-draft-release/README.md); [`cargo-publish`](../cargo-publish/README.md) runs behind it.

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
| `token` | `${{ github.token }}` | Token for the API reads. |

## Outputs

| Output | Description |
| --- | --- |
| `verified` | `"true"` when the tag is annotated and GitHub verifies its signature. |
| `commit` | The commit the tag points at. |
| `reason` | GitHub's verification reason (e.g. `valid`). |

## Notes

- The verification is GitHub's own, read through the API: no keyring on the runner, and a signature from a key that no account with the tagger identity has registered fails.
- Lightweight tags are refused.
- A non-tag ref without a `tag` input is a wiring error and fails regardless of `warn-only`.
- A tag ruleset restricts who may create, update or delete release tags (the shipped `.github/rulesets/tags-maintainer-only.json`); a `required_signatures` rule on tags refuses only pushes that introduce unsigned commits and never checks the tag object's signature.
  This gate is where the signature is enforced.
