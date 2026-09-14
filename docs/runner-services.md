# Runner services: the `.rust-ci-env` contract

A self-hosted runner host can offer per-host services to the jobs it runs: a
compile-cache backend for [`sccache`](../README.md#sccache), a crates.io
pull-through for [`crates-mirror`](../README.md#crates-mirror).
This document is the contract between the host operator who provisions those
services and the rust-ci actions that consume them.

## The file

The host writes a dotenv file named `.rust-ci-env` **beside the runner's work
directory**: `dirname($RUNNER_WORKSPACE)`, the directory that also holds
rust-cache's `.rust-ci-local-target` marker.
On a hosted runner that is `/home/runner/work`; inside a job container it
appears at `/__w`, because the work tree is bind-mounted while the runner's
own environment is not.
That asymmetry is why this is a file and not host-level environment.

A missing file means a plain runner: every consuming action no-ops in its
`auto` mode, so one workflow runs unchanged on hosted and self-hosted
runners.

## Format

- One `KEY=VALUE` per line; `#` starts a comment line; blank lines are
  ignored.
- Values are single-line, printable characters only, at most 2048 bytes.
  No quoting, no escaping: a value is everything after the first `=`,
  verbatim.
- Keys must match the vocabulary below.
  Consumers fail the job loudly on a malformed line; a host misconfiguration
  must not silently degrade into an uncached build.

## Key vocabulary

| Key | Consumer | Meaning |
|---|---|---|
| `SCCACHE_*` | `sccache` action | Imported verbatim into the job environment as sccache's backend configuration (e.g. `SCCACHE_WEBDAV_ENDPOINT`, `SCCACHE_BUCKET` + `SCCACHE_ENDPOINT`, `SCCACHE_REDIS_ENDPOINT`). The host picks the backend and names it here. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | `sccache` action | The S3 backend's credentials, paired with `SCCACHE_BUCKET` + `SCCACHE_ENDPOINT`. The only non-`SCCACHE_*` keys the action imports; WebDAV and Redis carry their auth inside `SCCACHE_*` instead. |
| `RUST_CI_CRATES_MIRROR` | `crates-mirror` action | A `sparse+http(s)://…/` registry URL of the host-local crates.io pull-through; written into `$CARGO_HOME/config.toml` as the crates-io source replacement. |

Unknown `SCCACHE_*` keys flow through (they belong to sccache), and the three
S3 credential vars above are imported alongside them; any other key fails the
consuming action.

## Operational expectations for the host

- Write the file at instance boot, before the runner takes jobs, readable by
  the runner user (0644 is fine; see the trust note).
  Ephemeral instances that reset their machine identity re-run their boot
  provisioning, so the file exists on every instance regardless of image.
- Values with `PASSWORD`, `TOKEN`, `SECRET` or `ACCESS_KEY` in their key are
  masked in job logs, but they are ordinary environment values inside the
  job: **everything in this file is readable by every job the runner
  executes.**
  Scope credentials to the cache backend alone, on a network the instances
  can reach but the world cannot.
- A compile cache written by untrusted jobs is a poisoning surface.
  Keep release/tag builds cache-off, or give trust tiers separate backends;
  that split belongs to the host and the workflows, not to these actions.
- The crates mirror serves under checksum protection (`Cargo.lock` pins the
  canonical crates.io hashes), so its integrity requirement is availability,
  not trust.

## Example

```sh
# /home/runner/actions-runner/_work/.rust-ci-env, written at instance boot.
SCCACHE_WEBDAV_ENDPOINT=http://10.160.0.1:9980/sccache
RUST_CI_CRATES_MIRROR=sparse+http://10.160.0.1:9980/crates/index/
```

With that in place, a workflow gets both services with:

```yaml
- uses: gronke/rust-ci/.github/actions/sccache@main        # auto: no-op without the file
- uses: gronke/rust-ci/.github/actions/crates-mirror@main  # auto: no-op without the file
# … cargo steps …
- uses: gronke/rust-ci/.github/actions/sccache-stats@main  # late: hit/miss facts for timing-report
```
