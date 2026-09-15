# timing-start

Begin per-stage timing for a job: initialise the mark log under `RUNNER_TEMP`, record the runner's core count and OS, and start a background sampler that writes CPU, memory and disk figures every few seconds.
Pair it with [`timing-mark`](../timing-mark/README.md) at the top of each stage and [`timing-report`](../timing-report/README.md) as an `if: always()` last step; how the report measures is described there.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/timing-start@v1
  with:
    first-stage: setup          # names the interval up to the first timing-mark
    # sample-interval: "5"      # seconds; "0" records durations only
    # first-stage: ""           # sampler only; stages then come from the Actions API
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `sample-interval` | `"5"` | Seconds between resource samples. `"0"` records durations only. |
| `first-stage` | `setup` | Name for the interval that begins here and ends at the first `timing-mark`; on most jobs that is checkout and cache restore. Empty is the sampler-only form: no mark is laid down and `timing-report` derives the stages from the Actions API. |

## Outputs

| Output | Description |
| --- | --- |
| `timing-dir` | Directory holding the marks, samples and notes for this job; also exported as `RUST_CI_TIMING_DIR`. |

## Notes

- Sampling reads `/proc/stat` and `/proc/meminfo`, so it is Linux-only; on other runners the durations are still recorded and the report says the sampler was unavailable.
- A tick reads `/proc/stat` and `/proc/meminfo` and runs `df` on the filesystem of the directory the action ran from.
- The sampler runs detached (`nohup setsid`) so it survives step boundaries; `timing-report` stops it, and it also exits when its pid file disappears or after six hours.
- Running `timing-start` twice in one job discards the earlier marks with a warning; only the last start is measured.
- The state directory is `$RUNNER_TEMP/rust-ci-timing` (`marks.tsv`, `samples.tsv`, `notes.tsv`, `sampler.pid`).
