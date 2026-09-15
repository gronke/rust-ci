# sccache-stats

Record what sccache delivered as `cache.sccache.*` facts for the `timing-report` Cache section, plus the raw `sccache --show-stats` output in a log group.
Use it as a late step after the builds it accounts for, in jobs that ran [`sccache`](../sccache/README.md).

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/sccache-stats@v1
  if: always()
```

## Inputs

None.

## Notes

- A no-op unless `RUSTC_WRAPPER` is an executable whose `--version` reports sccache, however it was installed.
- Records `cache.sccache` as `<hits> hits / <misses> misses of <requests> compile requests`, and `cache.sccache.errors` when the error count is not zero.
- The facts need `jq`; without it only the log group is written.
- Never fails the job: a broken stats query costs the numbers, not the build.
- Composite actions have no post hooks, hence the separate late step, the same split as `rust-cache` and `rust-cache-save`.
