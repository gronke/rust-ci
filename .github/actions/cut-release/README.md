# cut-release

Start a release: cut the changelog's `[Unreleased]` section for the declared version, push `release/vX.Y.Z`, open the merge-back pull request, and dispatch the release pipeline on the branch.
Run it from a `workflow_dispatch` workflow on the default branch; [`.github/workflows/cut.yml`](../../workflows/cut.yml) is the reference.

## Usage

```yaml
permissions:
  contents: write        # push the release branch
  pull-requests: write   # open the merge-back pull request
  actions: write         # dispatch the release pipeline
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0     # the merge-back needs history
  - uses: gronke/rust-ci/.github/actions/install-toolchain@v1   # crate repositories: cargo metadata
  - uses: gronke/rust-ci/.github/actions/cut-release@v1
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `branch-prefix` | `release/v` | The release branch name is this prefix plus the version. |
| `base` | `""` | Base branch of the merge-back pull request (defaults to the repository's default branch). |
| `pipeline-workflow` | `release.yml` | Workflow file to dispatch on the release branch; empty skips the dispatch. |
| `merge-back` | `"true"` | Open the merge-back pull request. |
| `package` | `""` | Package name (required for a workspace with more than one member). |
| `version` | `""` | The version to release, overriding Cargo.toml resolution. Required for a repository without a Cargo.toml. |
| `working-directory` | `.` | Directory containing the crate or workspace. |
| `changelog` | `CHANGELOG.md` | Changelog path, relative to the working directory. |
| `date` | `""` | The date stamped on the released section and the citation file (defaults to today, UTC). |
| `citation` | `CITATION.cff` | Citation File Format path; its top-level `version:` and, where present, `date-released:` are stamped. A missing file is skipped, an empty value disables the stamp. |
| `token` | `${{ github.token }}` | Token for the push, the merge-back pull request, and the dispatch. |
| `git-user-name` | `github-actions[bot]` | Committer identity for the release commit. |
| `git-user-email` | `41898282+github-actions[bot]@users.noreply.github.com` | Committer email for the release commit. |
| `dry-run` | `"false"` | Derive the version and branch and cut the changelog in the working tree, but push, open and dispatch nothing. |

## Outputs

| Output | Description |
| --- | --- |
| `version` | The released version. |
| `branch` | The release branch name. |

## Notes

- The branch guard runs first: an existing `release/vX.Y.Z` on origin refuses before the changelog is touched.
- The dispatch is explicit because a push made with the workflow token triggers no workflows.
- The merge-back needs the repository setting "Allow GitHub Actions to create and approve pull requests".
- A pull request opened with the workflow token triggers no CI; pass a machine-user or App token with matching `git-user-*` inputs when it must.
- The release commit is `chore: release vX.Y.Z` and carries the changelog and, when stamped, the citation file.
