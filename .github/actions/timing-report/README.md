# timing-report

Render the timing report to the job summary: per-stage durations with their share of the job and, where the sampler ran, peak CPU and memory per stage plus a CPU shape across it.
Use it as the last step of a job with `if: always()`, after [`timing-start`](../timing-start/README.md) and any [`timing-mark`](../timing-mark/README.md) steps; it also works alone, deriving the stages from the Actions API.

## Usage

```yaml
permissions:
  actions: read          # only needed for the mark-free form
steps:
  - uses: gronke/rust-ci/.github/actions/timing-start@v1
  - uses: gronke/rust-ci/.github/actions/timing-mark@v1
    with:
      name: build
  - run: cargo build --release
  - uses: gronke/rust-ci/.github/actions/timing-report@v1
    if: always()
    id: timing
  - run: echo "slowest stage ${{ steps.timing.outputs.slowest-stage }}"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `title` | `Where the time went` | Heading for the summary section. |
| `order` | `duration` | `duration` lists the slowest stage first; `chronological` keeps step order. |
| `columns` | `"12"` | Sparkline width per stage. Wider resolves a stage's phases; narrower keeps the table compact. |
| `token` | `${{ github.token }}` | Token used to read the job's per-step timings from the Actions API when the workflow places no `timing-mark` steps. Needs `actions: read`. |

## Outputs

| Output | Description |
| --- | --- |
| `report-path` | The rendered Markdown report on disk (`<timing-dir>/report.md`). |
| `total-seconds` | Sum of every stage's duration. |
| `slowest-stage` | Name of the longest stage. |
| `slowest-seconds` | Duration of the longest stage. |

## How it measures

Stages come from in-band marks: `timing-start` and each `timing-mark` append an epoch-millisecond boundary to `marks.tsv`, and the report closes the last stage with its own timestamp.
Without any mark, the report reads the job's completed steps from the Actions API (`GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`, needs `actions: read`) and uses each step's start as a boundary; this form also captures pre-step stages such as "Initialize containers" that in-job marks cannot see, at one-second resolution.
Marks win when present; `first-stage: ""` on `timing-start` is the sampler-only form, which runs the sampler but lays down no mark, so the stages still come from the API.
CPU is the busy share of all cores per sampling interval, computed from `/proc/stat` deltas between consecutive ticks rather than from a load average, so it attributes to the stage it was spent in.
Memory is `MemTotal - MemAvailable` from `/proc/meminfo`; the table shows the peak per stage.
The CPU shape splits a stage into `columns` buckets and draws the peak busy share of each as a block character; a full block is every core busy.
A stage that never fills a block is waiting on something (a link step, a database, one serialized test group) and will not get faster on a bigger runner; a stage that pins every core is compute-bound and will.
Samples are bucketed into stages by timestamp, so the sampler is stopped before its file is read and the last stage's samples are complete.
`GITHUB_STEP_SUMMARY` is a separate file per step, so a later step cannot read the summary back; the report is also written to `report-path`, which can be asserted on, uploaded as an artifact or diffed between two runs.
Notes contributed by other actions (`rust-cache`, `rust-cache-save`, `sccache-stats`) render as a Cache section under the table.

## Notes

- With no marks and no usable token, the report warns and exits 0.
- Without samples (non-Linux runner, `sample-interval: "0"`, or no `timing-start`) the table degrades to duration and share columns; the header repeats the sampler note when `timing-start` ran.
- The API path needs `jq` and `curl` on the runner; the default `github.token` works once the job grants `actions: read`.
- Do not read `GITHUB_STEP_SUMMARY` in a later step to check the report; use `report-path`.
