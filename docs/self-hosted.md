# Self-hosted runners

A self-hosted runner can offer per-host services to the jobs it runs: a compile-cache backend for `sccache`, a crates.io pull-through for `crates-mirror`, and a work tree that persists between jobs for `rust-cache`.
The actions read that offer from the job environment and from their inputs, nothing else.

## What the actions read

| Variable | Read by | Meaning |
| --- | --- | --- |
| `SCCACHE_*` | `sccache` | sccache's own backend configuration, for example `SCCACHE_WEBDAV_ENDPOINT`, `SCCACHE_BUCKET` with `SCCACHE_ENDPOINT`, `SCCACHE_REDIS_ENDPOINT` or `SCCACHE_DIR`; credentials such as `AWS_ACCESS_KEY_ID` are ordinary variables next to them. |
| `RUST_CI_CRATES_MIRROR` | `crates-mirror`, `rust-cache` with `cache-registry: auto` | A `sparse+http(s)://.../` registry URL of a crates.io pull-through, written into `$CARGO_HOME/config.toml` as the crates-io source replacement; `rust-cache` then skips the registry archive, since the mirror serves the same downloads without the transfer. |
| `RUST_CI_LOCAL_TARGET=1` | `rust-cache` with `local-target: auto` | The runner keeps its work tree between jobs, so `target/` stays on disk instead of travelling through the cache. Never set it on ephemeral runners. |

One rule for every `auto`: the mode activates when its variable is present and non-empty, and does nothing otherwise.
Hosted runners carry none of these variables, so one workflow runs unchanged on both.

## How a host sets them

Use the runner's job-started hook.
It runs on the host at the start of every job, before any job container is created, and the lines it appends to `$GITHUB_ENV` become the job's environment.
Every later step sees them, including the steps of a `container:` job, because the runner passes the job environment into each `docker exec`.

```sh
#!/bin/sh
# /usr/local/lib/ci/job-started.sh
{
  # A credential-free S3 endpoint on the host: an object proxy that signs
  # the requests itself, so the job holds no key.
  echo "SCCACHE_ENDPOINT=http://10.0.0.1:9982"
  echo "SCCACHE_BUCKET=build-cache"
  echo "SCCACHE_REGION=auto"
  echo "SCCACHE_S3_KEY_PREFIX=sccache"
  echo "SCCACHE_S3_USE_SSL=false"
  echo "SCCACHE_S3_NO_CREDENTIALS=true"
  echo "RUST_CI_CRATES_MIRROR=sparse+http://10.0.0.1:9981/index/"
} >> "$GITHUB_ENV"
# A credential is masked before it is written: echo "::add-mask::$secret"
```

Point the runner at the script with `ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/lib/ci/job-started.sh`, either in the `.env` file of the runner directory or in the environment of the runner's service, and restart the runner.
GitHub documents the hook under "Running scripts before or after a job".

Other routes, for completeness:

- A workflow may set the same variables itself, from `env:`, `vars.*` or `container.env`; an unset variable yields an empty value, which the actions treat as absent.
- Variables in the runner's `.env` alone reach the steps of bare jobs, never the steps of a `container:` job, and never the `env` expression context.
- `container.options: -e NAME` copies a variable from the runner's process environment into one workflow's container.
- `runner.environment` is `github-hosted` or `self-hosted`, so a fleet whose self-hosted runners keep their work tree can pass `local-target: ${{ runner.environment == 'self-hosted' }}` and pick `mode: gha` for sccache on hosted runners.

## Trust

Everything the hook exports is readable by every job the runner executes, third-party actions included.
Scope credentials to the cache backend alone, on a network the runners can reach and the world cannot.
A compile cache written by untrusted jobs is a poisoning surface: keep release builds cache-off, or give trust tiers separate backends.
The crates mirror serves under `Cargo.lock` checksum protection, so its requirement is availability, not trust.

## Limits

The sealed Docker actions pin `CARGO_HOME`, forward `CARGO_.*` only and build with `--network=none`, so neither sccache nor the mirror reaches them; their compile cache is the `target-dir` mount.
Inside a `container:` job use a network backend: a directory on the host is not visible there.
sccache runs one server per host and port, and the action restarts it with the current job's configuration; a runner that executes jobs concurrently sets `SCCACHE_SERVER_PORT` per job.
