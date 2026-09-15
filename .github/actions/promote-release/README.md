# promote-release

Promote a candidate from within the pipeline, or defer to the release manager, as `sign-tags` selects.
Run it as the last step of a candidate build, after [`release-guidance`](../release-guidance/README.md).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/promote-release@v1
  with:
    version: ${{ env.VERSION }}
    marker-tag: ${{ steps.draft.outputs.marker }}
    # sign-tags: manual     # explicit; empty auto-detects from the tag rulesets
    # moving-major: "true"  # advance v<MAJOR> on an off-mode promotion
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | (required) | The version being released (no leading `v`). |
| `marker-tag` | (required) | The candidate marker tag this build created (e.g. `v1.2.3-rc2`). |
| `sign-tags` | `""` | `manual` defers to the release manager; `off` promotes from the pipeline. Empty auto-detects from the repository's tag rulesets. |
| `moving-major` | `"false"` | Advance the moving `v<MAJOR>` tag after an `off`-mode promotion; prereleases and backports skip. |
| `token` | `${{ github.token }}` | Token for the ruleset probe, the tag push, and the release edit. |
| `git-user-name` | `github-actions[bot]` | Committer identity for the promoted tag. |
| `git-user-email` | `41898282+github-actions[bot]@users.noreply.github.com` | Committer email for the promoted tag. |
| `working-directory` | `.` | Directory of the checked-out repository. |

## Outputs

| Output | Description |
| --- | --- |
| `promoted` | `"true"` when the pipeline created and published the final tag; `"false"` when deferred to the release manager. |
| `mode` | The effective `sign-tags` mode (`manual` or `off`). |

## Notes

- Auto-detection: an active signature-requiring tag ruleset covering `v<version>` means `manual`, none means `off`, unreadable rulesets mean `manual`; a rule scoped to `v*-sig` companions does not cover the version.
- `off` creates the annotated final tag on the built commit with the marker's message, pushes it, publishes the draft, and with `moving-major` advances the major in one job; a workflow-token tag push triggers no second run.
- An explicit `off` under a signature rule covering `v<version>` errors before anything is pushed; retarget the rule or use `manual`.
- A re-run with `v<version>` already on this commit skips the tag push; the same version on a different commit is an error.
- An unsigned promotion binds provenance to whoever holds the token; the ruleset files under `.github/rulesets/` set up the signed alternative.
