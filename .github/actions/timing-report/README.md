# timing-report

Render the timing report to the job summary: per-step durations with their share of the job and, where the sampler ran, peak CPU and memory per step plus a CPU shape across it.
Use it as the last step of a job with `if: always()`, after [`timing-start`](../timing-start/README.md); it also works alone, for durations without the sampler's columns.

## Usage

```yaml
permissions:
  contents: read
  actions: read          # the per-step timings come from the Actions API
steps:
  - uses: gronke/rust-ci/.github/actions/timing-start@v1
  - run: cargo build --release
  - run: cargo test --release
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
| `token` | `${{ github.token }}` | Token used to read the job's per-step timings from the Actions API. Needs `actions: read`. Empty skips the API and the report shows the job totals. |

## Outputs

| Output | Description |
| --- | --- |
| `report-path` | The rendered Markdown report on disk (`<timing-dir>/report.md`). |
| `total-ms` | Sum of every stage's duration in milliseconds. |
| `total-seconds` | Sum of every stage's duration. |
| `slowest-stage` | Name of the longest stage; the job's id when the report has no per-step stages. |
| `slowest-seconds` | Duration of the longest stage. |

## How it measures

Stages are the job's steps: the report reads the job's completed steps from the Actions API (`GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`, needs `actions: read`) and uses each step's start as a boundary, at one-second resolution; this also captures pre-step stages such as "Initialize containers".
Without the API (no token, no `actions: read`, a 403 or 404) the report shows the job totals from `timing-start` to itself as one stage named after the job, warns that per-step stages need `actions: read`, and exits 0.
CPU is the busy share of all cores per sampling interval, computed from `/proc/stat` deltas between consecutive ticks rather than from a load average, so it attributes to the stage it was spent in.
Memory is `MemTotal - MemAvailable` from `/proc/meminfo`; the table shows the peak per stage.
The CPU shape splits a stage into `columns` buckets and draws the peak busy share of each as a block character; a full block is every core busy.
A stage that never fills a block is waiting on something (a link step, a database, one serialized test group) and will not get faster on a bigger runner; a stage that pins every core is compute-bound and will.
Samples are bucketed into stages by timestamp, so the sampler is stopped before its file is read and the last stage's samples are complete.
`GITHUB_STEP_SUMMARY` is a separate file per step, so a later step cannot read the summary back; the report is also written to `report-path`, which can be asserted on, uploaded as an artifact or diffed between two runs.
Notes contributed by other actions (`rust-cache`, `rust-cache-save`, `sccache-stats`) render as a Cache section under the table.

## Notes

- The report never fails a job: without the API it shows the totals; without `timing-start` and without the API it warns and exits 0.
- Without samples (non-Linux runner, `sample-interval: "0"`, or no `timing-start`) the per-step table degrades to duration and share columns and the totals form has no table; the heading line repeats the sampler note when `timing-start` ran.
- The API path needs `jq`, `curl` and GNU `date` on the runner (macOS runners get the totals); the default `github.token` works once the job grants `actions: read`.
- The Actions API lists a step a few seconds after it completes, so the step right before `timing-report` may be missing from the table; run the report after a short final step when that step matters.
- Do not read `GITHUB_STEP_SUMMARY` in a later step to check the report; use `report-path`.
