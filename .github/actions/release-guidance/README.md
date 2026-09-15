# release-guidance

Write the release manager's next steps for a freshly built draft pre-release into the run's step summary and the log: accept, reject, and what goes live next.
Run it as the last step of a successful candidate build, after [`draft-release`](../draft-release/README.md).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/release-guidance@v1
  with:
    version: ${{ env.VERSION }}
    marker-tag: ${{ steps.draft.outputs.marker }}
    commit: ${{ github.sha }}
    draft-url: ${{ steps.draft.outputs.url }}
    # go-live: publish-draft   # default: signed-tag
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | (required) | The version the draft pre-release carries (no leading `v`). |
| `marker-tag` | (required) | The candidate marker tag this build created (e.g. `v1.2.3-rc2`). |
| `commit` | (required) | The commit the marker sealed, which the accept commands tag. |
| `go-live` | `signed-tag` | How the draft goes live: `signed-tag` or `publish-draft`. |
| `tag-script` | `""` | Repository-relative tagging helper featured in the accept commands (called as `<tag-script> <commit> -s`); plain git commands when empty. `signed-tag` mode only. |
| `draft-url` | `""` | URL of the draft release, linked from the summary when set. |
| `token` | `${{ github.token }}` | Token for the `publish-draft` mode's tag-ruleset probe. |

## Notes

- `signed-tag` renders `git tag -s -F <(git tag -l --format='%(contents)' <marker>) v<version> <commit>` and a push by name, so the signed tag copies the marker's message.
- `publish-draft` renders merge-then-publish: `gh release edit v<version> --draft=false [--prerelease=false] --target <merged commit>`, plus the optional signed `v<version>-sig` companion.
- In `publish-draft` mode the step errors at candidate time when an active tag ruleset requires signatures on `v<version>` itself, since GitHub creates that tag unsigned on publish.
- A release-candidate version (a hyphen in the version) keeps the pre-release flag in the rendered flip command.
- The summary carries three `###` blocks: accept, reject, and what the go-live triggers.
