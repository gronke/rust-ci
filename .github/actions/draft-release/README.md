# draft-release

Build the reviewable candidate: render the changelog's released section into `release-notes.md`, create or refresh the `v<version>` draft pre-release with it as the body, and push the next `v<version>-rcN` marker tag on the run's commit with the same notes as its message.
Run it on every push of the release branch, followed by [`release-guidance`](../release-guidance/README.md) and optionally [`promote-release`](../promote-release/README.md).

## Usage

```yaml
- uses: actions/checkout@v7
- uses: gronke/rust-ci/.github/actions/draft-release@v1
  id: draft
  with:
    version: ${{ needs.gate.outputs.version }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | (required) | The version being drafted (no leading `v`). |
| `package` | `""` | Workspace member whose changelog section is rendered; empty resolves the sole package. |
| `changelog` | `CHANGELOG.md` | Path of the changelog, relative to `working-directory`. |
| `title` | `""` | Subject line for the notes and the draft; empty means `v<version>`. |
| `token` | `${{ github.token }}` | Token for the release create/edit and the marker push. |
| `git-user-name` | `github-actions[bot]` | Committer identity for the marker tag. |
| `git-user-email` | `41898282+github-actions[bot]@users.noreply.github.com` | Committer email for the marker tag. |
| `working-directory` | `.` | Directory of the checked-out repository. |

## Outputs

| Output | Description |
| --- | --- |
| `marker` | The candidate marker tag this run pushed (e.g. `v1.2.3-rc2`). |
| `url` | URL of the draft release. |

## Notes

- Two renderings are written: `release-notes.md` (Markdown, the release body) and `release-tag.md` (plain text, the marker's message and, through the guidance command, the signed final tag's).
- The marker number is one past the highest existing `v<version>-rcN` on the remote, read from one refs listing.
- The marker is created locally first, so run it on a checkout without fetched tags (actions/checkout's default); a stale local rcN would shadow the push.
- A rejected marker push (GH013) means the tag ruleset must let Actions create unsigned `v*-rc*` tags; exclude them from creation-restricting and signature-requiring rules.
- The draft is created with `--draft --prerelease`; an existing release of that name only gets its notes refreshed.
