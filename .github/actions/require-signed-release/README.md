# require-signed-release

Answer whether a release commit carries a verified human signature, as the gate for registry publication.
Pair it with [`cargo-publish`](../cargo-publish/README.md): feed `signed` into its `publish` input, so an unsigned release rehearses with `--dry-run` instead of uploading.

## Usage

```yaml
permissions:
  id-token: write   # crates.io Trusted Publishing
steps:
  - id: sig
    uses: gronke/rust-ci/.github/actions/require-signed-release@v1
    with:
      version: ${{ needs.gate.outputs.version }}
      attestation-tags: "v*-sig"
  - if: steps.sig.outputs.signed == 'true'
    id: auth
    uses: rust-lang/crates-io-auth-action@v1
  - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
    with:
      publish: ${{ steps.sig.outputs.signed }}
      registry-token: ${{ steps.auth.outputs.token }}
      allow-already-published: "true"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | `""` | The released version (no leading `v`); ignored when `tag` is set. |
| `tag` | `""` | The release tag to gate; default `v<version>`. |
| `attestation-tag` | `""` | A pushed companion (e.g. `github.ref_name` on a `v*-sig` trigger); the published release on the commit it seals is the one gated, and `release-tag` and `version` are derived from it. |
| `require-published` | `"false"` | `"true"`: a release that is still a draft, or absent, is an error rather than an unsigned answer. |
| `unsigned-guidance` | `"false"` | `"true"`: an unsigned verdict also writes the commands that create and push the signed companion into the step summary. |
| `attestation-tags` | `*` | Glob another tag must match to count as an attestation (e.g. `v*-sig`). |
| `accept-release-tag` | `"true"` | A verified-signed release tag satisfies the gate. |
| `accept-attestation-tag` | `"true"` | A verified-signed tag on the same commit satisfies the gate. |
| `accept-signed-commit` | `"false"` | A verified signature on the release commit itself satisfies the gate. |
| `accept-web-flow` | `"false"` | A web-flow (GitHub UI merge) signature counts for `accept-signed-commit`. |
| `token` | `${{ github.token }}` | Token for the API reads. |

## Outputs

| Output | Description |
| --- | --- |
| `signed` | `"true"` when a verified signature covers the release commit. |
| `source` | `release-tag`, `attestation-tag`, `commit`, or empty. |
| `attestation` | The attestation tag's name, when that source satisfied the gate. |
| `commit` | The commit the release tag points at. |
| `release-tag` | The release tag that was gated; derived from `attestation-tag` when given. |
| `version` | That tag without its leading `v`. |

## Notes

- Sources are checked in order: the release tag, an attestation tag matching `attestation-tags` on the same commit, then (opt-in) the commit signature; lightweight tags carry no signature and are skipped.
- `accept-signed-commit` is off by default because GitHub signs UI-made rebase and squash merges with its own web-flow key; even when on, web-flow counts only with `accept-web-flow`.
- The derivation from `attestation-tag` is by commit identity: a commit carrying no published release, or more than one, is refused rather than guessed.
- Everything is read through the API; no checkout is needed, and a workflow triggered by a companion pushed later (see `attestation-tag`) can complete a publication that was waiting for it.
- `rust-lang/crates-io-auth-action` sets a `token` output (needs `id-token: write`) and never exports `CARGO_REGISTRY_TOKEN`.
