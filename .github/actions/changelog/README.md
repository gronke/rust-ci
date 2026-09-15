# changelog

Keep a "Keep a Changelog" `CHANGELOG.md` coherent with the crate's declared version, and render released sections as tag messages or release bodies.
Run `check` on every pull request; `cut` and `notes` are what [`cut-release`](../cut-release/README.md) and [`draft-release`](../draft-release/README.md) call.

## Usage

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0   # the baseline scan reads the release tags
- uses: gronke/rust-ci/.github/actions/changelog@v1
  with:
    mode: check
```

## Modes

- `check`: while `[Unreleased]` carries entries, the version must exceed the baseline by SemVer precedence (`1.0.0-rc1 < 1.0.0`), a `**Breaking` entry needs a minor bump on 0.x or a major bump from 1.x, and a pre-release version refuses `### Added`, `### Removed` and `**Breaking` entries.
  Without a version it only checks that the newest released section is tagged, warning when it is not.
- `cut`: rewrites `## [Unreleased]` into `## [X.Y.Z] - <date>`, turns the `[Unreleased]: .../compare/<prev>...HEAD` link into the released compare link, and exports `CHANGELOG_VERSION` into the job environment.
  Refuses an empty section, more than one `[Unreleased]` heading, or an existing `[X.Y.Z]` section.
- `notes`: writes the `[X.Y.Z]` section to `out`.
  `format: plain` drops backticks and `**`, turns `### Group` into `Group:` and leads with `title`; `format: markdown` keeps the section as authored and omits the title.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `mode` | (required) | `check`, `cut`, or `notes`. |
| `package` | `""` | Package name (required for a workspace with more than one member). |
| `working-directory` | `.` | Directory containing the crate or workspace. |
| `changelog` | `CHANGELOG.md` | Changelog path, relative to the working directory. |
| `version` | `""` | The version, overriding Cargo.toml resolution in every mode. Required for `cut` on a repository without a crate; `notes` falls back to the newest released section. |
| `out` | `release-notes.md` | `notes`: file the rendered notes are written to, relative to the working directory. |
| `title` | `""` | `notes`: subject line led before the section in `plain` format. |
| `format` | `plain` | `notes`: `plain` or `markdown`. |
| `baseline-version` | `""` | `check`: the version the crate must exceed. Defaults to the greatest release tag in the checkout by SemVer precedence, or `0.0.0` when there is none. |
| `date` | `""` | `cut`: the date stamped on the released section (defaults to today, UTC). |

## Notes

- A stable version's baseline skips `-rcN` tags, since candidate markers reserve nothing; a pre-release version counts them.
- The version ladder is the `version` input, else Cargo.toml through `cargo metadata`.
- In `markdown` format inline code keeps `@tokens` such as `@import` from autolinking as @mentions in the release body.
- SemVer compares `rc9` and `rc10` lexically, so `rc10` orders below `rc9`; number candidates `-rc.9`, `-rc.10` when double digits are in reach.
- Build metadata (`+build`) is accepted and ignored for precedence.
