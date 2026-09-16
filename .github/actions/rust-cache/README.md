# rust-cache

Restore cargo's download cache and, on request, the build `target/` directory through `actions/cache`.
Use it before the build steps of a runner-native or `container:` job; pair it with [`rust-cache-save`](../rust-cache-save/README.md) as the last step of every job that should write the target entry back.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/rust-cache@v1
  with:
    prefix: build            # one cache family per job
    cache-target: "true"     # also restore target/ (off by default)
    # local-target: "auto"   # keep target/ on a runner whose work tree persists
    # save: "false"          # registry restore-only, for pure consumers
    # stats: "true"          # hit kind and restored size in the step summary
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `prefix` | `rust` | Cache-family name, so independent jobs keep separate caches. |
| `save` | `"true"` | Save the registry entry at job end. `"false"` restores only; the target entry is restore-only here regardless. |
| `cache-target` | `"false"` | Also restore the build `target/` directory. |
| `local-target` | `"false"` | `"true"`, `"false"` or `"auto"`: keep `target/` on the runner instead of transferring it. Requires `cache-target`. |
| `target-dir` | `target` | Workspace-relative target directory to restore. Ignored when local-target is active. |
| `lockfiles` | `**/Cargo.lock` | Glob of lockfiles whose hash keys the caches. |
| `cache-directories` | `""` | Extra newline-separated paths added to the registry entry. |
| `stats` | `"false"` | Record the hit kind and restored sizes in the step summary and for the `timing-report` Cache section. |

## Outputs

| Output | Description |
| --- | --- |
| `target-cache-hit` | `"true"` when the target entry restored from its exact key. Empty under local-target, which restores nothing. |

## How it works

Two cache entries, split by churn rate.
The registry entry holds `registry/index`, `registry/cache` and `git/db` under the cargo home, never `registry/src` (cargo re-extracts it from the tarballs); it is keyed on `prefix`, `runner.os` and the lockfile hash, falls back to a `<prefix>-<os>-registry-` prefix match, and saves at job end through `actions/cache`'s post step unless `save: "false"`.
The target entry adds a hash of `rustc -V` to the key, so a toolchain bump never reuses incompatible artifacts, and is restore-only here: a restore-key fallback plus save-on-new-key would accrete every generation's stale artifacts into the next, so the save lives in `rust-cache-save`, which prunes first.
The key, directory and hit state reach `rust-cache-save` as `RUST_CI_TARGET_KEY`, `RUST_CI_TARGET_DIR` and `RUST_CI_TARGET_HIT` in `$GITHUB_ENV`.

`CARGO_INCREMENTAL` defaults to `0` and `CARGO_TERM_COLOR` to `always`; a value already present in the job environment is left untouched and flows through, into the Docker actions included.
No build profile is imposed.
The cargo home is `$CARGO_HOME` when set, else `$HOME/.cargo`, so a container image that bakes the toolchain elsewhere (for example `/opt/cargo`) is cached correctly.

`local-target` requires `cache-target`: `"true"` without it fails, `"auto"` stays off.
`"auto"` activates when the job environment carries `RUST_CI_LOCAL_TARGET=1`, which a host whose work tree persists provides ([docs/self-hosted.md](../../../docs/self-hosted.md)); ephemeral runners must not set it, because the directory dies with the instance.
It sets `CARGO_TARGET_DIR` to `<work root>/.rust-ci-target/<prefix>`, outside the workspace, because `actions/checkout` defaults to `clean: true` and runs `git clean -ffdx`, which deletes an in-workspace `target/` however persistent the disk is.
Consumers must read `CARGO_TARGET_DIR` rather than assume `./target`.
The target restore is skipped and no key is handed over, so `rust-cache-save` skips as well; the registry entry still goes through `actions/cache`, because the cargo home usually lives in the toolchain image rather than the work tree.
The directory is shared per prefix across every repository on the runner and never pruned; the host reclaims disk by wiping `.rust-ci-target`.
When `RUNNER_WORKSPACE` is empty the action falls back to the transfer.

## Notes

- `stats` walks the restored trees with `du`, which takes seconds on a multi-gigabyte target; pair it with `stats: "true"` on `rust-cache-save` for the prune ratio.
- `stats` records `cache.target` as `exact hit`, `restore-key fallback (another generation)` or `miss` (under local-target `local (kept on the runner)` or `local, cold`); a fallback carries artifacts cargo may or may not reuse, which a build log alone does not show.
- The GitHub Actions cache holds 10 GB per repository by default and removes entries after 7 days without access; cache writes are scoped per ref.
