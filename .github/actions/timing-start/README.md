# timing-start

Start the timing state for a job under `RUNNER_TEMP`: record the runner's core count and OS, and start a background sampler that writes CPU, memory and disk figures every few seconds.
Pair it with [`timing-report`](../timing-report/README.md) as an `if: always()` last step, which attributes the samples to the job's steps; how the report measures is described there.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/timing-start@v1
  # with:
  #   sample-interval: "5"      # seconds; "0" records durations only
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `sample-interval` | `"5"` | Seconds between resource samples. `"0"` records durations only. |

## Outputs

| Output | Description |
| --- | --- |
| `timing-dir` | Directory holding the samples and notes for this job, `$RUNNER_TEMP/rust-ci-timing`. |

## Notes

- Sampling reads `/proc/stat` and `/proc/meminfo`, so it is Linux-only; on other runners the report keeps the durations and says the sampler was unavailable.
- A tick reads `/proc/stat` and `/proc/meminfo` and runs `df` on the filesystem of the directory the action ran from.
- The sampler runs detached (`nohup setsid`) so it survives step boundaries; `timing-report` stops it, and it also exits when its pid file disappears or after six hours.
- Running `timing-start` twice in one job stops the earlier sampler and discards its state with a warning; only the last start is measured.
- The state directory is `$RUNNER_TEMP/rust-ci-timing` (`samples.tsv`, `notes.tsv`, `sampler.pid`); every timing action and the cache statistics resolve it without an input.
