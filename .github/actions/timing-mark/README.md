# timing-mark

Record the start of a stage for the timing report: one step per stage, placed immediately before the work it names.
Use it between [`timing-start`](../timing-start/README.md) and [`timing-report`](../timing-report/README.md); drop every mark to have the report derive the stages from the Actions API instead.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/timing-mark@v1
  with:
    name: build
- run: cargo build --release
- uses: gronke/rust-ci/.github/actions/timing-mark@v1
  with:
    name: test
- run: cargo test --release
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `name` | (required) | Stage name as it should read in the summary table. Tabs and newlines are collapsed to spaces. |

## Notes

- A mark is a boundary, not a duration: a stage runs from its mark to the next one, and `timing-report` closes the last stage with its own timestamp.
- The interval between a mark and the next one includes whatever runs between the two steps (a cache restore, for instance), so naming a stage for the step that follows attributes that cost to it.
- The action only appends to `marks.tsv` and never fails the job; a mark before `timing-start`, or without one, still records.
- When any mark exists, the report uses the marks and does not consult the Actions API.
