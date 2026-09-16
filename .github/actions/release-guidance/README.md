# release-guidance

Write the release manager's next steps for a freshly built draft pre-release into the run's step summary and the log: accept, reject, and what the tag push triggers.
Run it as the last step of a successful candidate build, after [`draft-release`](../draft-release/README.md).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/release-guidance@v1
  with:
    version: ${{ env.VERSION }}
    marker-tag: ${{ steps.draft.outputs.marker }}
    commit: ${{ github.sha }}
    draft-url: ${{ steps.draft.outputs.url }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | (required) | The version the draft pre-release carries (no leading `v`). |
| `marker-tag` | (required) | The candidate marker tag this build created (e.g. `v1.2.3-rc2`). |
| `commit` | (required) | The commit the marker sealed, which the accept commands tag. |
| `tag-script` | `""` | Repository-relative tagging helper featured in the accept commands (called as `<tag-script> <commit> -s`); plain git commands when empty. |
| `draft-url` | `""` | URL of the draft release, linked from the summary when set. |

## Notes

- The accept block renders `git tag -s -F <(git tag -l --format='%(contents)' <marker>) v<version> <commit>` and a push by name, so the signed tag copies the marker's message; with `tag-script` it renders `<tag-script> <commit> -s` instead.
- The summary carries three `###` blocks: `Accept: sign and push the tag`, `Reject: nothing to unwind`, and `What the tag push triggers`.
- The tag push runs the pipeline's final path: [`require-signed-tag`](../require-signed-tag/README.md), the seal against the newest marker, the draft flip, the moving major, and, for a crate, the registry upload behind the gate.
