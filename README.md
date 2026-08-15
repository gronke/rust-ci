# Rust CI/CD

Reusable GitHub Actions for Rust CI/CD.
Install a toolchain, run the lint-and-test gate, and check a crate's release readiness — without depending on third-party actions whose behaviour drifts with the runner image.

Each action is a composite action under [`.github/actions/`](.github/actions/).
A repository consumes one with `uses: gronke/rust-ci/.github/actions/<name>@<ref>`.
During bring-up, pin `@main`; once the interface is stable we cut a `v1` tag plus a moving major tag, and consumers pin `@v1`.

## Umbrella workflow

For the standard sealed pipeline — build the toolchain image, warm the cache once, then `fmt` + `clippy` + `test`, an optional cross-target check, and an optional MSRV build, all sealed (`--network=none`, `--offline`) — a consumer's whole CI is one reusable-workflow call:

```yaml
jobs:
  ci:
    uses: gronke/rust-ci/.github/workflows/ci.yml@v1
    with:
      targets: wasm32-unknown-unknown   # optional: sealed cross-checks
```

| Input | Default | Description |
| --- | --- | --- |
| `rust-version` | `latest` | `rust:<tag>` base for the image (or `msrv`). |
| `targets` | `""` | Space-separated rustup targets to cross-check (empty runs none). |
| `features` | `""` | Feature flag for the sealed lint-and-test leg. |
| `msrv` | `true` | Also verify the crate on its declared MSRV. |
| `working-directory` | `.` | Crate directory. |

The individual actions below remain for pipelines that compose their own flow.

## Actions

### `install-toolchain`

Installs Rust via rustup — toolchain, components, and targets — and puts `~/.cargo/bin` on `PATH`.
Works on Linux, macOS and Windows; when a runner ships no Rust at all (e.g. `windows-11-arm`) it bootstraps the arch-appropriate `rustup-init` instead of failing.

```yaml
- uses: gronke/rust-ci/.github/actions/install-toolchain@main
  with:
    toolchain: stable          # or an MSRV like 1.77.2
    components: rustfmt clippy
    targets: ""                # e.g. x86_64-apple-darwin
```

### `lint-and-test`

Runs `cargo fmt --check`, `cargo clippy --all-targets -D warnings`, and `cargo test` for one feature universe.
Call it once per universe for a default / all-features / no-default-features matrix, enabling `fmt` on a single leg so it does not repeat.

```yaml
- uses: gronke/rust-ci/.github/actions/lint-and-test@main
  with:
    features: ""               # or --all-features / --no-default-features
    fmt: "true"
```

### `cargo-out-dir`

Builds a package and exposes its build script's `OUT_DIR` — where `build.rs` bakes generated assets — as the `out-dir` output.
It is the build producer itself: the directory comes from its own `cargo build`, matched against the exact `cargo pkgid` of the requested package (dependencies' build scripts emit the same message reason, so exactness matters), and an unresolvable package fails the step instead of emitting an empty path.
Don't pair it as a cheap resolver after a differently-configured build — a different feature or profile set owns a different fingerprint directory; give it the same `profile`/`args` instead.
For sealed container builds, `cargo-docker` carries the same resolution via `out-dir-package`.

```yaml
- id: bake
  uses: gronke/rust-ci/.github/actions/cargo-out-dir@main
  with:
    package: my-app            # required only for a workspace with >1 member
- run: cp -r "${{ steps.bake.outputs.out-dir }}/dist"/. site/
```

### `check-release-readiness`

Verifies a crate is ready to release.
On a `v*` tag it asserts the tag matches the crate version.
For a publishable crate it runs `cargo publish --dry-run` and checks the version is not already on crates.io.
A crate with `publish = false` is validated for tag/version coherence only, so the action is equally useful for internal crates.
In a workspace, `package:` selects the member whose version is asserted; `version.workspace = true` inheritance resolves through cargo metadata, so a unified workspace version works by naming any inheriting member — see [Cargo workspaces](docs/release-flow.md#cargo-workspaces).
A repository without a Cargo.toml declares its version through the `version` input — or, absent both, through its changelog's newest released section — and is validated for coherence only.

```yaml
- uses: gronke/rust-ci/.github/actions/check-release-readiness@main
  with:
    package: my-crate          # required only for a workspace with >1 member
    # expected-version: 1.2.3  # defaults to the pushed v* tag
    # version: 1.2.3           # non-crate repos: the declared version
```

### `changelog`

Keeps a [Keep a Changelog](https://keepachangelog.com) `CHANGELOG.md` coherent with the crate's declared version.
`mode: check` gates a pull request: entries under `[Unreleased]` require the crate version to exceed the last released baseline by SemVer precedence (the greatest release tag, pre-release tags included — so fetch tags), a `**Breaking:**` entry requires more than a patch bump, and a pre-release version (`1.0.0-rc1`) tolerates only stabilization content — feature entries reset the version to the next regular release (see [docs/release-flow.md](docs/release-flow.md)).
`mode: cut` turns `[Unreleased]` into the released section for the crate's version, rewrites the `.../compare/<prev>...HEAD` link, and exports `CHANGELOG_VERSION` for later steps.
`mode: notes` renders a released version's section as plain text — inline Markdown stripped (`**`, backticks), `### Group` → `Group:`, reference-link definitions dropped, an optional `title` led as a subject line — into `out` (default `release-notes.md`), for a git tag message or release body.
The `version` input overrides Cargo.toml resolution in every mode; a repository without a crate names the version at cut time (`notes` falls back to the newest released section, and `check` degrades to section/tag coherence — the newest released section must be tagged).

**Fragments.** A pull request may add `changelog.d/<slug>.<section>.md` — bullet lines only, one of `added`/`changed`/`deprecated`/`removed`/`fixed`/`security` as the section suffix — instead of editing `[Unreleased]`: parallel branches then never collide on the same region of one file.
`check` reads fragments as pending content (the version, breaking-bump, and pre-release rules apply to the combination, with a fragment's feature signal read from its filename suffix), and `cut` folds them into the released section — existing `###` groups keep their order and gain the matching fragments, new sections append in canonical order — and deletes the files from the release commit.
Direct `[Unreleased]` entries and fragments may coexist; the `fragments` input moves the directory.

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0             # the check derives its baseline from the tags
- uses: gronke/rust-ci/.github/actions/changelog@main
  with:
    mode: check                # or: cut / notes (notes takes `version`, writes release-notes.md)
```

### `cut-release`

Starts a release for the version Cargo.toml declares — or the `version` input where there is no crate: runs the [changelog](#changelog) cut, pushes the `release/vX.Y.Z` branch with the release commit, opens the merge-back pull request, and dispatches the release pipeline on the branch (explicitly — pushes made with the workflow token trigger no workflows).
Refuses an existing release branch before the changelog is touched; `dry-run` derives the `version`/`branch` outputs and cuts only the working tree.
The job needs `contents`, `pull-requests`, and `actions` write permissions, and the repository setting that allows Actions to create pull requests.

```yaml
- uses: gronke/rust-ci/.github/actions/cut-release@main
  # with:
  #   version: 1.2.0                   # non-crate repos name the version to cut
  #   pipeline-workflow: release.yml   # dispatched on the new branch; empty skips
  #   git-user-name / git-user-email   # a machine-user or App identity lets the
  #                                    # merge-back pull request trigger CI
```

### `require-signed-tag`

Gates a release pipeline on a verified signed tag: the ref must be an annotated tag object whose signature GitHub verifies, read through the API — no keyring on the runner; lightweight tags refuse.
Requiring the signature is the workflow's preference: the gate refuses builds, only a repository tag ruleset prevents the tag — so the action warns when no active tag ruleset requires signatures, and `warn-only` turns refusals into warnings.
Outputs: `verified`, `commit` (what the tag seals), `reason`.

```yaml
- uses: gronke/rust-ci/.github/actions/require-signed-tag@main
  if: github.ref_type == 'tag'
```

### `release-guidance`

Writes the release manager's next steps into the run's step summary, as the last step of a candidate build: accept (fetch the markers, sign exactly the marker commit, push the tag by name — never `--tags`), reject (delete the draft and branch; nothing is consumed), and what the tag push triggers.

```yaml
- uses: gronke/rust-ci/.github/actions/release-guidance@main
  with:
    version: ${{ env.VERSION }}
    marker-tag: v${{ env.VERSION }}-rc${{ env.RC }}
    commit: ${{ github.sha }}
    # tag-script: scripts/tag-release.sh  # featured in the accept commands
```

### `draft-release`

Build the reviewable candidate in one step: render the changelog's released section into `release-notes.md`, create or refresh the draft pre-release it becomes the body of, and push the next unsigned `v<version>-rcN` marker carrying the same text. Outputs the marker tag and the draft URL — feed them to `release-guidance` (and `promote-release`).

```yaml
- uses: gronke/rust-ci/.github/actions/draft-release@v1
  id: draft
  with:
    version: ${{ needs.gate.outputs.version }}
```

### `publish-draft-release`

`seal-only: "true"` verifies the seal and stops — run it in the release gate so a mis-pointed tag fails in seconds rather than after every artifact job. Otherwise: publish the reviewed candidate in one step — seal the human-pushed final tag against the newest marker by tree, flip the draft live (a stable version sheds the pre-release flag), and optionally advance the moving `v<MAJOR>` to the highest stable release in its line — only ever onto a commit on the default branch.

```yaml
- uses: gronke/rust-ci/.github/actions/publish-draft-release@v1
  with:
    version: ${{ needs.gate.outputs.version }}
    moving-major: "true"
```

### `require-signed-release`

Answers whether a human signature covers a release commit — the gate for registry publication, in any go-live mode, and the step that makes an attestation companion load-bearing.
Three sources satisfy it, checked in order: the release tag itself is an annotated tag GitHub verifies; another verified-signed tag points at the same commit; or — opt-in — the commit carries a verified signature, with GitHub's web-flow key (which signs UI merges, so nearly every commit on a UI-merged repository) excluded unless `accept-web-flow` says otherwise.
Unsigned is an answer, not a failure: feed `signed` into [`cargo-publish`](#cargo-publish)'s `publish` and an unsigned release rehearses instead of uploading, so a signature pushed later — retroactively — completes the publication.
`attestation-tags` narrows what counts as a companion; the default accepts any signed tag on the release commit, because a verified human signature there *is* an attestation whatever it is named — name the shape (`v*-sig`, `sig/*`) where the statement should be deliberate rather than incidental.
On a signature-triggered job, pass the pushed companion as `attestation-tag` instead of a version: the release it seals is derived by commit — any naming convention works — and `require-published` makes a draft an error rather than an answer.
Outputs: `signed`, `source` (`release-tag` · `attestation-tag` · `commit`), `attestation`, `commit`, `release-tag`, `version`.

```yaml
- id: sig
  uses: gronke/rust-ci/.github/actions/require-signed-release@main
  with:
    version: 1.2.3                # or: tag: v1.2.3
    attestation-tags: "v*-sig"    # default "*": any signed tag on that commit
    # on a v*-sig trigger instead, derive the release from the companion:
    # attestation-tag: ${{ github.ref_name }}
    # require-published: "true"
- if: steps.sig.outputs.signed == 'true'
  uses: rust-lang/crates-io-auth-action@v1
- uses: gronke/rust-ci/.github/actions/cargo-publish@main
  with:
    publish: ${{ steps.sig.outputs.signed }}
```

### `cargo-publish`

Publish the crate to crates.io — or rehearse it. `publish` is `"false"` by default, which runs `cargo publish --dry-run` and reads no credential at all; `publish: true` checks the version against crates.io and uploads, which only a yank can undo. Only releases matching `tag-pattern` are published — the default `^v[0-9]+\.[0-9]+\.[0-9]+$` admits stable releases only, so a prerelease or a bare major is a notice and a skip rather than an upload. Prefer Trusted Publishing over a stored secret: `rust-lang/crates-io-auth-action` exports a short-lived `CARGO_REGISTRY_TOKEN` this action picks up. This publishes the *crate*; the GitHub Release is `publish-draft-release`.

```yaml
permissions: { id-token: write, contents: write }
steps:
  - uses: rust-lang/crates-io-auth-action@v1        # short-lived token, no stored secret
  - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
    with:
      publish: "true"                               # omit for a dry run
      # registry-token: ${{ secrets.CARGO_REGISTRY_TOKEN }}   # classic-token fallback
```

### `promote-release`

Promotes a candidate from within the pipeline, or defers to the release manager — governed by `sign-tags`.
`manual` (the mode an active signature-requiring tag ruleset implies when nothing is configured) is a no-op beside the guidance: a human signs.
`off` creates the annotated, unsigned final tag on the built commit with the marker's message, publishes the draft, and optionally advances the moving major — one job, since a workflow-token tag push triggers no second run.
Unreadable rulesets resolve to `manual`; the shipped [`/.github/rulesets/`](.github/rulesets) files set up the signed alternative.

```yaml
- uses: gronke/rust-ci/.github/actions/promote-release@main
  with:
    version: ${{ env.VERSION }}
    marker-tag: ${{ steps.marker.outputs.marker }}
    # sign-tags: manual    # explicit; empty auto-detects from the tag rulesets
    # moving-major: "true" # advance v<MAJOR> on an off-mode promotion
```

### `rust-cache`

Caches cargo for CI and **defaults** incremental compilation off — pure cost in CI (no edit→recompile loop), and the main thing that balloons `target/`.
An explicit `CARGO_INCREMENTAL` (set at the workflow/job level) is obeyed — for the occasional variant build that is faster with it on — and flows through to the Docker actions via their `CARGO_.*` forwarding. The action imposes no build profile; set `CARGO_*` vars to tune the build.
The cargo home is resolved from `CARGO_HOME` when set — container images that bake the toolchain outside `$HOME/.cargo` (e.g. `/opt/cargo`) are cached correctly.
Place it before your build/test steps.

Two independent cache entries, split by churn rate:

- The **registry** entry (index + `.crate` tarballs + git db — never `registry/src`, cargo re-extracts it) is small, toolchain-independent and bounded by the `Cargo.lock` key.
  It restores and saves here (`actions/cache`'s post step); `save: "false"` makes it restore-only.
- The **target** entry (opt-in via `cache-target`) is **restore-only in this action**: a restore-key fallback plus save-on-new-key would accrete every generation's stale artifacts into the next.
  Saving it back is [`rust-cache-save`](#rust-cache-save)'s job.

```yaml
- uses: gronke/rust-ci/.github/actions/rust-cache@main
  with:
    prefix: build            # cache family — use a distinct one per job
    cache-target: "true"     # also restore target/ (off by default)
    # save: "false"          # registry restore-only, for pure consumers
```

### `rust-cache-save`

The save half of `rust-cache`'s target entry: prunes `target/` down to **dependency artifacts** — workspace-member objects, final binaries, examples, incremental state and docs are rebuilt or relinked on any commit, so caching them only grows the archive and the tar/zstd staging that can fill the runner disk at save time — then uploads under the exact key the restore computed (handed over via `$GITHUB_ENV`, so the halves cannot diverge).
Call it as the **last step of the job**; composite actions have no post hooks, so this is what runs "after the build, before the upload".
An exact restore hit skips prune and save (the stored entry is already pruned and current).
The restore-everywhere/save-on-main pattern: PR jobs omit this action (or pass `save: "false"`) and read what the default branch's warmup maintains — per-branch target saves are multi-gigabyte duplicates nobody else can restore.

```yaml
- uses: gronke/rust-ci/.github/actions/rust-cache-save@main
  if: always()               # optional: save even when a test step failed
  with:
    save: ${{ github.ref == 'refs/heads/main' }}
    # working-directory: .   # where `cargo metadata` names the members to prune
```

### `build-image`

Builds the toolchain image — `rust:<version>` plus clippy, rustfmt, and jq — locally and loads it into the Docker daemon, so the Docker actions below run against a local `rust-ci:latest` tag with no registry.
Run it once before the Docker actions; `cache: "true"` caches the added layer (the `rust:<version>` base is pulled from Docker Hub).
Pass `rust-version: msrv` to build at the crate's declared MSRV (read from `Cargo.toml`), so the whole Docker pipeline runs on the support floor and a dependency that raises its MSRV fails the normal gate.
See [the action's README](.github/actions/build-image/README.md).

```yaml
- uses: gronke/rust-ci/.github/actions/build-image@main
  with:
    rust-version: "1"      # any rust:<tag>; default "latest" (or `msrv` → Cargo.toml)
    cache: "true"          # cache the added layer (opt-in)
```

### `cargo-docker`

Runs one cargo command inside the pinned image, **sealed**: non-root, all Linux capabilities dropped (`--cap-drop=ALL`), no privilege escalation (`--security-opt=no-new-privileges`), the repo mounted read-only, and — by default — `--network=none` with `cargo --offline` (run `cargo-fetch` first to warm the cache).
The low-level primitive for a network-isolated build: dependency `build.rs` and proc-macros execute during compilation, and with no network they can't exfiltrate or fetch a payload.

```yaml
- uses: gronke/rust-ci/.github/actions/cargo-fetch@main      # warm the cache (the one networked step)
- uses: gronke/rust-ci/.github/actions/cargo-docker@main      # sealed build — offline, --network none
  with:
    args: "build --release --locked --features full"  # do NOT add --offline; `offline` controls it
    # offline: "false"   # opt out to fetch-as-it-builds (networked)
```

`out-dir-package` additionally resolves that package's build-script `OUT_DIR` (a sealed JSON-messages `cargo build` replay — give `out-dir-args` the main build's profile/features so the replay is free; other flags still resolve correctly, against their own configuration) and exposes it as the `out-dir` output, translated from the container's `/work/target` to the host side of `target-dir` so later steps can copy from it.
Exact package-id matching needs the image's cargo ≥1.77; older images fail loudly with "no build-script OUT_DIR".

```yaml
- id: bake
  uses: gronke/rust-ci/.github/actions/cargo-docker@main
  with:
    args: "build --release --locked"
    out-dir-package: my-app
    out-dir-args: "--release --locked"
- run: cp -r "${{ steps.bake.outputs.out-dir }}/dist"/. site/
```

### `msrv`

Compiles a crate on its **declared MSRV** (`rust-version` in `Cargo.toml`) inside a container built at exactly that toolchain, so a dependency that raises its own MSRV is caught on the PR that pulls it in — not only at release time.
The image *is* the MSRV, so a plain sealed `cargo check` is the check; there is no MSRV tool to install and no toolchain to select.
If you already run the sealed Docker pipeline, point `build-image` at `rust-version: msrv` and the normal lint-and-test gate enforces the MSRV across fmt/clippy/test — this action is then an explicit floor gate (a cheap `cargo check`), most useful when your main CI runs natively or on stable.
See [the action's README](.github/actions/msrv/README.md).

```yaml
- uses: gronke/rust-ci/.github/actions/msrv@main
  with:
    package: my-crate           # required for a workspace with >1 member
    features: "--features full" # optional; the flag passed to cargo check
    # rust-version: "1.95"      # optional override; default reads Cargo.toml
```

### `cargo-install`

Install a cargo-based CLI tool into a shared, hardened cargo cache so later sealed runs can use it.
See [the action's README](.github/actions/cargo-install/README.md) for the security model, inputs, and examples.

### `cargo-use`

Run a `cargo-install`'d tool from the shared cache, sealed and network-isolated by default.
See [the action's README](.github/actions/cargo-use/README.md).

### `route-git-token`

Route git fetches ON THE RUNNER through a short-lived token: an `url.insteadOf` rewrite exported as `GIT_CONFIG_*` environment entries (they die with the job — nothing lands in a gitconfig file, which matters on self-hosted runners) plus `CARGO_NET_GIT_FETCH_WITH_CLI` so cargo's fetches honor it.
The unsealed sibling of `cargo-fetch`'s `git-token` input, for jobs that run plain `cargo build` or `git clone` outside the container.
The defaults speak GitHub, but any authenticated https git host works: `host:` and `username:` carry the host's convention (GitLab OAuth: `oauth2`; Bitbucket: `x-token-auth`), and `path:` optionally scopes the rewrite to a namespace — nested groups included.
Invocations append, so two tokens for two hosts or namespaces coexist.

```yaml
- uses: gronke/rust-ci/.github/actions/route-git-token@main
  with:
    token: ${{ steps.deps-token.outputs.token }}
    path: my-org
```

### `publish-dry-run`

A release gate split into **network-with-no-code** then **code-with-no-network**.
A networked prep does the publish checks *without building* — cache warm-up, tag ↔ `Cargo.toml` version, a not-already-published probe, and `cargo publish --dry-run --no-verify` — so no dependency code runs while it has the network.
Then the **verify-build runs sealed**: `cargo package --offline` under `--network=none`, so the dependency `build.rs` / proc-macros it compiles and executes can't reach the network. (`cargo publish --dry-run` can't run here — it always contacts the registry, which `--offline` rejects.)

```yaml
- uses: gronke/rust-ci/.github/actions/publish-dry-run@main
  with:
    package: my-crate          # required only for a workspace with >1 publishable member
    # expected-version: 1.2.3  # defaults to the pushed v* tag
    # git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}   # only for private git deps
```

The runner-based `check-release-readiness` above runs the same checks without Docker (networked, on the runner) for repositories not using the sealed flow.

## Release flow

Every action above is a base operation with its own contract; a repository composes them under its own conditions — whether publishing a release triggers automation, and to what degree, is the consumer's definition.
Six actions assume the Keep-a-Changelog convention and the `rcN` candidate markers: [`changelog`](#changelog), [`cut-release`](#cut-release), [`draft-release`](#draft-release), [`publish-draft-release`](#publish-draft-release), [`release-guidance`](#release-guidance), and [`promote-release`](#promote-release).
They compose into the showcased branch-based flow — [`cut-release`](#cut-release) starts the release, the draft/marker loop builds candidates, and the go-live seals and publishes — with release-candidate manifest versions (`1.0.0-rc1`) first-class: the candidate is a release, and `-rc` stays reserved for stabilization.
[docs/release-flow.md](docs/release-flow.md) carries the full guide: the candidate loop, the signed and publish-go-live modes, the reference workflows, and the repository configuration the showcase relies on.

A pipeline that keeps its own release process needs none of that.
The registry ending bolts onto any CI — the version comes from Cargo.toml, the notes are yours, no changelog is read:

```yaml
on:
  push:
    tags: ["v*"]

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: crates-io
    permissions:
      id-token: write # crates.io Trusted Publishing
    steps:
      - uses: actions/checkout@v7
      # tag/version coherence, packaging, not-already-published
      - uses: gronke/rust-ci/.github/actions/check-release-readiness@v1
      # optional: upload only under a human signature — the tag itself, a
      # signed companion on the same commit, or (opt-in) the signed commit;
      # unsigned, the publish below rehearses instead of uploading
      - id: sig
        uses: gronke/rust-ci/.github/actions/require-signed-release@v1
        with:
          tag: ${{ github.ref_name }}
      - if: steps.sig.outputs.signed == 'true'
        uses: rust-lang/crates-io-auth-action@v1
      - uses: gronke/rust-ci/.github/actions/cargo-publish@v1
        with:
          publish: ${{ steps.sig.outputs.signed }}
```

## Passing env into the container (Docker actions)

The Docker actions (`cargo-fetch`, `cargo-docker`, `cargo-install`, `cargo-use`, `lint-and-test-docker`, `publish-dry-run`) run cargo inside the pinned image, so a variable set on the runner does not reach the build unless the action forwards it.
Each action forwards a configurable set, controlled by three inputs:

- `env-include` — a POSIX-ERE regex matched against variable **names** (anchored full-name); default `CARGO_.*`, so `CARGO_BUILD_JOBS`, `CARGO_NET_RETRY`, `CARGO_TERM_COLOR`, … flow in with no per-variable wiring.
- `env-exclude` — names to drop from the included set; **exclusion wins over inclusion**. Defaults to the action-owned `CARGO_HOME|RUSTUP_HOME|CARGO_TARGET_DIR`.
- `env` — extra literal `KEY=VALUE` lines (one per line) forwarded verbatim, for per-step values (a step-level `env:` on the `uses:` line does not reach a composite action's steps, so this input is how you pass per-invocation values).

Set the variables at the job or workflow level so the action's inner step sees them, then widen the pattern as needed:

```yaml
env:
  CARGO_BUILD_JOBS: "4"
  RUSTFLAGS: "-D warnings"
jobs:
  ci:
    steps:
      - uses: gronke/rust-ci/.github/actions/lint-and-test-docker@main
        with:
          env-include: "(CARGO_|RUST).*"   # forward cargo + rust vars
          # env-exclude defaults to the owner-vars; add your own to widen the blacklist
          env: |                            # literal extras, always forwarded
            MY_BUILD_FLAG=1
```

Widening `env-include` to `.*` forwards **everything on the runner**, including secrets such as `GITHUB_TOKEN` — prefer a tight `env-include`, or add sensitive names to `env-exclude`.
Regardless of the inputs, the actions always pin `CARGO_HOME`, `RUSTUP_HOME`, and `CARGO_TARGET_DIR` to their in-container paths (after `--env-file`, last-wins), so a forwarded copy can never redirect the mounted cache or target and break the sealed build.

## Private git dependencies (cargo-fetch)

A `Cargo.toml` git dependency on a **private** repository can't be cloned anonymously, and `cargo-fetch` runs cargo inside the container, so the credential has to reach the container's git — not the runner's.
Pass a token through the `git-token` input.
When it is set, `cargo-fetch` configures git to authenticate `github.com` fetches as `x-access-token` and forces cargo to fetch via the git CLI (so the rewrite applies); when it is empty the step is unchanged, so public-only workspaces need nothing.

```yaml
- name: Cargo fetch
  uses: gronke/rust-ci/.github/actions/cargo-fetch@main
  with:
    git-token: ${{ secrets.PRIVATE_DEP_TOKEN }}
```

The token must carry `contents: read` on every private dependency repository.
The default `GITHUB_TOKEN` only grants access to the workflow's own repository, so a cross-repository dependency needs a fine-grained PAT or a GitHub App installation token, stored as a secret.
See [docs/private-git-dependencies.md](docs/private-git-dependencies.md) for the GitHub App setup and an in-workflow minting example.
The sealed `lint-and-test-docker` passes run `--offline` against the cache `cargo-fetch` populated, so they need no token.
Jobs that build on the runner instead of in the container route the same token with [`route-git-token`](#route-git-token).

## Cache-size operations

GitHub grants each repository 10 GB of cache before least-recently-used eviction starts; entries also expire seven days after their last access.
Generations pile up (one target entry per `Cargo.lock` state, plus PR-scoped duplicates that only the same PR can restore), so an occasional look pays off.

Inventory, largest first:

```sh
gh cache list -R <owner>/<repo> --limit 100 \
  --json key,sizeInBytes,ref,lastAccessedAt \
  --jq 'sort_by(-.sizeInBytes)[] | "\(.sizeInBytes/1048576|floor) MB  \(.ref)  \(.key)"'
```

Delete superseded default-branch generations of one family, keeping the newest:

```sh
gh cache list -R <owner>/<repo> --ref refs/heads/main \
  --json id,key,createdAt \
  --jq '[.[] | select(.key | startswith("<prefix>-"))] | sort_by(.createdAt) | .[:-1][].id' \
  | xargs -rn1 gh cache delete -R <owner>/<repo>
```

Drop a pull request's leftovers (also auto-cleaned about two weeks after the PR closes):

```sh
gh cache list -R <owner>/<repo> --ref refs/pull/<n>/merge --json id --jq '.[].id' \
  | xargs -rn1 gh cache delete -R <owner>/<repo>
```

## Self-test

[`.github/workflows/selftest.yml`](.github/workflows/selftest.yml) runs every action against the fixture crate in [`fixtures/sample-crate`](fixtures/sample-crate/) on each push and pull request.
The actions are therefore exercised end-to-end before any consumer relies on them.


## Motivation

GitHub Actions have huge potential for supply-chain attacks. Repeating the same setup across repositories was tedious or required using and combining various other third-party actions, none of which is hardened against malicious build.rs scripts in test-dependencies, that potentially receive less attention than the release dependency tree. What purpose does it have to execute both in the same job context? As Archer would say: "That's how you get ants". Given how quick Rust build caches can grow and how time-consuming it can be to pass artifacts between jobs, Docker is available in GitHub Actions and provides easier means of compartmentalization.
The Docker actions take that further: a build runs sealed — non-root, all capabilities dropped, no privilege escalation, and `--network=none` against a cache a separate `cargo-fetch` warmed — so a dependency `build.rs` or proc-macro compiles but cannot reach the network. `cargo-fetch` is the one networked step; `publish-dry-run` keeps that same seal around the verify-build (`cargo package`), where dependency code is otherwise executed during a release — while the publish checks, which run no build, keep the network.

## Status and licence

Reusable across Rust projects; released under the MIT licence (see [LICENSE](LICENSE)).
