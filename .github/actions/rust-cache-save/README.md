# rust-cache-save

Prune `target/` down to dependency artifacts and upload it under the exact key [`rust-cache`](../rust-cache/README.md) computed.
Use it as the last step of a job that ran `rust-cache` with `cache-target: "true"` and should write the target entry back; consumer-only jobs omit it or pass `save: "false"`.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/rust-cache-save@v1
  if: always()               # optional: save even when a build step failed
  with:
    save: ${{ github.ref == 'refs/heads/main' }}
    # working-directory: .   # where `cargo metadata` names the members to prune
    # stats: "true"          # record the pruned size and the prune ratio
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `save` | `"true"` | Upload the pruned target. Pass the expression `github.ref == 'refs/heads/main'` for the restore-everywhere, save-on-main pattern. |
| `working-directory` | `.` | Workspace directory whose `cargo metadata` names the members to prune. |
| `stats` | `"false"` | Record the pruned size, and the share the prune removed when `rust-cache` measured the tree before the build, for the `timing-report` Cache section. |

## How it works

`rust-cache` hands over `RUST_CI_TARGET_KEY`, `RUST_CI_TARGET_DIR` and `RUST_CI_TARGET_HIT` through `$GITHUB_ENV`.
Every step skips when the key is empty (no `cache-target`, or `local-target` active) or when the restore was an exact hit, whose stored entry is already pruned and current.
The prune removes `incremental`, `examples` and `doc` directories, the top-level files of every profile directory (final binaries and their dep-info), and the `deps/`, `.fingerprint/` and `build/` entries of the workspace members named by `cargo metadata --no-deps`.
Dependency artifacts stay; everything else is rebuilt or relinked on any commit and only grows the archive and the tar/zstd staging that can fill the runner disk at save time.
Without a `Cargo.toml` in `working-directory` the directory is saved unpruned.
The upload uses `actions/cache/save` under the handed-over key, so the two halves cannot diverge.

## Notes

- Composite actions have no post hooks, so this step is what runs after the build and before the upload; place it last.
- Per-branch target saves are multi-gigabyte entries scoped to that ref (cache writes are scoped per ref), hence the save-on-main pattern.
- The prune ratio is reported only when `rust-cache` ran with `stats: "true"` and measured the tree before the build.
- `DRY_RUN=1` in the environment makes the prune script print what it would remove instead of removing it.
