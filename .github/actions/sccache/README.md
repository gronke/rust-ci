# sccache

Install a pinned [sccache](https://github.com/mozilla/sccache) release as `RUSTC_WRAPPER` and start its server.
Use it before the build steps of a runner-native or `container:` job; the backend comes from `SCCACHE_*` variables in the job environment or from `mode: gha`, and [`sccache-stats`](../sccache-stats/README.md) records the hits as a late step.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/sccache@v1
  with:
    # hosted: GitHub's cache service; self-hosted: the SCCACHE_* backend in the job env
    mode: ${{ runner.environment == 'github-hosted' && 'gha' || 'auto' }}
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `server-startup-timeout-ms` | `"30000"` | How long the client waits for the server, written as `server_startup_timeout_ms` into a configuration file the action points `SCCACHE_CONF` at; a job that sets `SCCACHE_CONF` itself, or has a default file, keeps its own. |
| `mode` | `auto` | `auto` activates when a non-empty `SCCACHE_*` variable is set, `on` activates regardless, `off` changes nothing, `gha` uses GitHub's cache service. |
| `namespace` | `""` | A path below the configured backend's key prefix (`release/linux-amd64`), so tiers or platforms share one backend without sharing objects; ignored without a backend. |
| `version` | `"0.17.0"` | sccache release to install, pinned together with the checksums. |
| `sha256-x86_64` | `67c4a96dd237c1f518f6b36083f270f9976d516f1e57fce891755ea782e50006` | SHA256 of the x86_64-unknown-linux-musl release archive. |
| `sha256-aarch64` | `821a86343191aa1cbab74bd42f9e93c9a63bf85e4742945f40d3ae84193c1c77` | SHA256 of the aarch64-unknown-linux-musl release archive. |

## Outputs

| Output | Description |
| --- | --- |
| `active` | `"true"` when sccache was installed and `RUSTC_WRAPPER` exported. |
| `bin` | Absolute path of the installed sccache binary; empty when inactive. |

## How it works

The release archive is downloaded by version and verified against the pinned sha256 before extraction into `$RUNNER_TEMP/rust-ci-sccache`; inside a job container that is the bind-mounted `_work/_temp`, so the absolute `RUSTC_WRAPPER` path stays valid in every later step without touching `PATH`.
sccache reads its own `SCCACHE_*` configuration, so every backend it supports works; a present-but-empty variable does not count as a backend.
[docs/self-hosted.md](../../../docs/self-hosted.md) shows how a host provides the variables.
`CARGO_INCREMENTAL` defaults to `0` because incremental output is uncacheable; an explicit value is obeyed.
A server left by an earlier job is stopped and a fresh one started, so a broken install fails this step; backend reachability proves itself on first use, because sccache connects lazily.

`mode: gha` exports `ACTIONS_RUNTIME_TOKEN` (masked) and `ACTIONS_RESULTS_URL` into the job environment through `actions/github-script`, which the runner otherwise hands only to JavaScript action steps, and sets `SCCACHE_GHA_ENABLED=true`.
It spends the repository's Actions cache: 10 GB per repository by default, entries removed after 7 days without access, writes scoped per ref, so pull-request objects never reach the default branch's scope.
It is never part of `auto`; a bare `SCCACHE_GHA_ENABLED` in the job environment without `mode: gha` fails this step instead of the first compile.

`namespace` puts the job's objects below the backend's key prefix: `release/linux-amd64` on a host prefix `sccache` reads and writes `sccache/release/linux-amd64/…`, so tiers or platforms share one backend without sharing objects.
It follows whichever backend the environment configures, in sccache's own fallback order (S3, Redis, Memcached, GCS, the gha version, Azure, WebDAV, OSS, then a subdirectory of a local `SCCACHE_DIR`), and is ignored when no backend is configured; a malformed value (anything but `[A-Za-z0-9._-]` segments joined by `/`) fails the step.
A namespace separates objects, not writers: every job that reaches the backend can still write any key, so a trust boundary needs a backend of its own.

## Notes

- Linux x86_64 and aarch64 only; any other platform fails the step.
- `on` without a backend warns: sccache then falls back to a local-disk cache that an ephemeral runner throws away.
- Every mode fetches `actions/github-script` at "Set up job", because the runner resolves a nested `uses` before its `if`.
- The sealed Docker actions are untouched: they pin `CARGO_HOME`, forward `CARGO_.*` only and build offline.
- sccache runs one server per host and port; a runner that executes jobs concurrently sets `SCCACHE_SERVER_PORT` per job.
- The server checks its storage before it answers and the client waits `server-startup-timeout-ms` for it; sccache's own default of ten seconds was crossed when several jobs' servers checked one WebDAV backend at once. The client's message reaches the log when the start fails.
