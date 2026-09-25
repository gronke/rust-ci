# sccache

Install a pinned [sccache](https://github.com/mozilla/sccache) release as `RUSTC_WRAPPER` and start its server.
Use it before the build steps of a runner-native or `container:` job; the backend comes from `SCCACHE_*` variables in the job environment, or, without one, from a named archive on GitHub's cache service, and [`sccache-stats`](../sccache-stats/README.md) records the hits as a late step.

## Usage

```yaml
- uses: gronke/rust-ci/.github/actions/install-toolchain@v1   # first: the toolchain keys the archive
- uses: gronke/rust-ci/.github/actions/sccache@v1
  with:
    archive: build                                    # used only where the runner offers no backend
    write: ${{ github.ref == 'refs/heads/main' }}     # pull requests read what main stored
- run: cargo build --locked
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `server-startup-timeout-ms` | `"30000"` | How long the client waits for the server, written as `server_startup_timeout_ms` into a configuration file the action points `SCCACHE_CONF` at; a job that sets `SCCACHE_CONF` itself, or has a default file, keeps its own. |
| `mode` | `auto` | `auto` activates when a backend is configured or an archive engages, `on` activates regardless, `off` changes nothing. |
| `archive` | `""` | Name of a GitHub Actions cache archive (`A-Za-z0-9._-`) that carries the local disk cache between runs when no backend is configured; one per job. Empty turns the fallback off. |
| `archive-size` | `"2G"` | `SCCACHE_CACHE_SIZE` of the archived directory, unless the job sets one; it bounds what the archive transfers. |
| `lockfiles` | `**/Cargo.lock` | Glob of the lockfile(s) whose hash keys the archive. |
| `namespace` | `""` | A path below the configured backend's key prefix (`release/linux-amd64`), so tiers or platforms share one backend without sharing objects; part of the archive's key beside an engaged archive, ignored without either. |
| `write` | `"true"` | `"false"` reads and stores nothing: the backend's own read/write mode on a backend, a restore without a save on an archive; the setting for pull requests beside a default branch that writes. |
| `version` | `"0.17.0"` | sccache release to install, pinned together with the checksums. |
| `sha256-x86_64` | `67c4a96dd237c1f518f6b36083f270f9976d516f1e57fce891755ea782e50006` | SHA256 of the x86_64-unknown-linux-musl release archive. |
| `sha256-aarch64` | `821a86343191aa1cbab74bd42f9e93c9a63bf85e4742945f40d3ae84193c1c77` | SHA256 of the aarch64-unknown-linux-musl release archive. |

## Outputs

| Output | Description |
| --- | --- |
| `active` | `"true"` when sccache was installed and `RUSTC_WRAPPER` exported. |
| `archive` | `"true"` when the named archive carries the cache, because no backend is configured. |
| `bin` | Absolute path of the installed sccache binary; empty when inactive. |

## Persistence

`write: "false"` makes a job a reader: it reads what others stored and stores nothing, while its compiles still run through the wrapper.
On a backend that is the backend's own read/write mode, set to `READ_ONLY` before the server starts (`SCCACHE_S3_RW_MODE`, `SCCACHE_WEBDAV_RW_MODE`, … `SCCACHE_LOCAL_RW_MODE` for a `SCCACHE_DIR`).
On an archive it is a restore without a save; the reader's own objects serve its later compiles and leave with the runner.
`"true"` exports nothing but one exception: sccache itself defaults GCS to `READ_ONLY`, so there `"true"` exports `SCCACHE_GCS_RW_MODE=READ_WRITE`; a mode the host set stays in force either way.
It is a client setting: a backend that accepts writes from any job still does.

## The archive

`archive` is the fallback for runners without a backend, GitHub's hosted ones among them.
The job's local disk cache (`$RUNNER_TEMP/rust-ci-sccache/cache`, bounded by `archive-size`) travels as one cache entry, restored before the server starts, since sccache indexes its disk cache at startup.
Every hit is then a local file read; the archive pays its transfer once per job instead of once per object.

The key is `sccache-<archive>-<os>-<arch>-<rustc hash>-<environment hash>-<lockfile hash>`, with a `namespace` below the archive name (`sccache-<archive>/<namespace>-…`), so jobs sharing an archive name under different namespaces are separate families.
The rustc hash is `norustc` when no rustc answers yet; installing the toolchain before this action, the demonstrated order, keys the archive to the toolchain.
The environment hash covers the job's `CARGO_*` variables as this step sees them, which sccache hashes into every object's key as well, all but `CARGO_MAKEFLAGS`, `CARGO_BUILD_JOBS`, `CARGO_ENCODED_RUSTFLAGS` and `CARGO_REGISTRIES_*`; an unset `CARGO_INCREMENTAL` counts as the `0` the action exports, a variable that a later step sets is not in it, and one whose value changes with every run makes every run a new entry.
Restore keys fall back to the newest archive of the same family, toolchain and environment, never further, since no compile could hit the objects of another.
sccache's keys also hold what the action cannot see: the compiler arguments, which carry the linker and the rustflags from cargo's configuration, and each registry crate's directory, which differs between a crates mirror and crates.io; jobs that differ there need a namespace each, or they restore an archive they cannot hit.

A writer saves at job end, and only when its exact key is new, so each toolchain and lockfile pair is saved once.
Cache entries are immutable, so an entry keeps what its first writer compiled: the objects of the dependencies, the bulk of a Rust build, which the lockfile hash names; the workspace's own crates recompile once their sources move on, and a later writer with the same key saves nothing.
The lockfile hash names what the archive holds only when the builds resolve against the committed lockfile, so build with `--locked`: a resolution that drifts compiles another dependency set, and the save lands under the hash taken before the build.

The entries spend the repository's Actions cache, 10 GB by default, with entries removed after 7 days without access, which is what `archive-size` is sized against.
A configured backend wins: beside one, the archive stays unused.

## Backends

sccache reads its own configuration, so every backend it supports works; [docs/self-hosted.md](../../../docs/self-hosted.md) shows how a host provides the variables.
The action detects the backend by the rules of the pinned release, because the namespace and the read/write mode are variables of that backend:

1. A multi-level chain (`SCCACHE_MULTILEVEL_CHAIN`).
2. A cache in sccache's configuration file: `SCCACHE_CONF`, or without it `$XDG_CONFIG_HOME/sccache/config` (`~/.config/sccache/config`).
3. The first `SCCACHE_*` backend in sccache's own fallback order: S3, Redis, Memcached, GCS, Azure (the container with the connection string), WebDAV, OSS, COS, then a local `SCCACHE_DIR`.

A present-but-empty variable does not count, and neither does a tuning variable alone (`SCCACHE_CACHE_SIZE`, a `SCCACHE_CONF` without a cache).
The first two activate `auto` and stay as they are configured, so `namespace` and `write: "false"` refuse them.

`namespace` puts the job's objects below the backend's key prefix: `release/linux-amd64` on a host prefix `sccache` reads and writes `sccache/release/linux-amd64/…`, and a local `SCCACHE_DIR` gains a subdirectory; a malformed value (anything but `[A-Za-z0-9._-]` segments joined by `/`) fails the step.
A namespace separates objects, not writers: every job that reaches the backend can still write any key, so a trust boundary needs a backend of its own.

Whenever the action sets a namespace, a read/write mode or an archive, it compares the cache location the started server reports with the detected backend; a mismatch, such as a backend sccache configures from a source the detection does not read, fails the step rather than storing past the namespace or the read-only mode.

## Troubleshooting

- The server reads its backend before it answers, so an unreachable backend fails the start, with the client's message in the log; an http(s) endpoint (`SCCACHE_ENDPOINT` on S3, and the WebDAV, OSS and COS endpoints) that gives no answer within three seconds is named in a warning first.
- The client waits `server-startup-timeout-ms` for the server; sccache's own default of ten seconds was crossed when several jobs' servers checked one WebDAV backend at once.
- `on` without a backend or an archive warns: sccache then falls back to a local-disk cache that an ephemeral runner throws away.
- A server left by an earlier job is stopped and a fresh one started; sccache runs one server per host and port, so a runner that executes jobs concurrently sets `SCCACHE_SERVER_PORT` per job.
- A job environment with `SCCACHE_GHA_ENABLED` or `SCCACHE_GHA_VERSION` fails the step (`mode: off` excepted, which changes nothing): sccache's own GitHub cache backend is not wired, since it spends one cache entry and one network round trip per object.
- `split-debuginfo = "unpacked"` (`-C split-debuginfo=unpacked`) writes `.dwo` files that sccache does not store, so a crate served from the cache comes without its debug info; `packed` keeps the DWARF objects inside the `.rlib`, and `debug = "line-tables-only"` for the dependencies needs no split at all.

## Notes

- Linux x86_64 and aarch64 only; any other platform fails the step.
- The release archive is verified against the pinned sha256 before extraction into `$RUNNER_TEMP/rust-ci-sccache` (`_lib/install-release.sh`); inside a job container that is the bind-mounted `_work/_temp`, so the absolute `RUSTC_WRAPPER` path stays valid in every later step without touching `PATH`.
- `CARGO_INCREMENTAL` defaults to `0` because incremental output is uncacheable; an explicit value is obeyed.
- Every job fetches `actions/cache` at "Set up job", because the runner resolves a nested `uses` before its `if`.
- The sealed Docker actions are untouched: they pin `CARGO_HOME`, forward `CARGO_.*` only and build offline.
