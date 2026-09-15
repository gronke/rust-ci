# publish-draft-release

Publish the reviewed candidate: seal the final tag against the newest `v<version>-rcN` marker by tree, flip the draft live, and optionally advance the moving `v<MAJOR>` tag.
Run it on the tag run of the release pipeline, and with `seal-only: "true"` in the gate job so a mis-pointed tag fails before any artifact job.

## Usage

```yaml
- uses: actions/checkout@v7
- uses: gronke/rust-ci/.github/actions/publish-draft-release@v1
  with:
    version: ${{ needs.gate.outputs.version }}
    moving-major: "true"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `seal-only` | `"false"` | `"true"` verifies the seal and stops: no flip, no moving major. |
| `tag-sha` | `""` | Commit the tag points at, when the run's own `GITHUB_SHA` is not it (a `release` event, a `workflow_dispatch`). Defaults to `GITHUB_SHA`. |
| `version` | (required) | The version being published (no leading `v`). |
| `moving-major` | `"false"` | Advance the moving `v<MAJOR>` tag after publishing; prereleases skip. |
| `token` | `${{ github.token }}` | Token for the seal probes, the release edit, and the major-tag push. |
| `git-user-name` | `github-actions[bot]` | Committer identity for the moving major tag. |
| `git-user-email` | `41898282+github-actions[bot]@users.noreply.github.com` | Committer email for the moving major tag. |
| `working-directory` | `.` | Directory of the checked-out repository. |

## Outputs

| Output | Description |
| --- | --- |
| `marker` | The candidate marker tag the publish was sealed against. |

## Notes

- The seal compares trees, not commits: a rebase-merged merge-back rewrites the SHA but carries the identical tree and is a valid tag target.
- No `v<version>-rcN` marker on the remote is an error; the pipeline publishes only reviewed candidates.
- A stable version (no semver hyphen) sheds the pre-release flag on the flip; build metadata (`+build`) counts as stable here.
- The moving major points at the highest stable `v<MAJOR>.x.y` tag and only at a commit reachable from the default branch; both are checked before the flip, so a refused move fails while the release is still a draft.
- Publishing the crate to crates.io is [`cargo-publish`](../cargo-publish/README.md).
