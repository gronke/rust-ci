#!/usr/bin/env bash
# Resolve a build script's OUT_DIR from a sealed build and translate it to
# the host — the runner-side companion of cargo-docker.sh. It runs two extra
# sealed invocations against the warm target: the exact package id, then a
# JSON-messages `cargo build` replay of the out-dir-package. The
# JSON parsing is host-side (_lib/out-dir.sh); the container only ever runs
# plain cargo, and the spec and the messages both carry /work-form paths, so
# host paths never enter the comparison.
#   OUT_DIR_PACKAGE  package whose build script to resolve
#   OUT_DIR_ARGS     extra args for the resolve build (never --offline)
# plus seal.sh's own environment (IMAGE, TARGET_DIR, CARGO_CACHE, OFFLINE, …).
set -euo pipefail

# shellcheck source=../_lib/seal.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/seal.sh"
# shellcheck source=../_lib/out-dir.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/out-dir.sh"
export CICD_DIR="$GITHUB_ACTION_PATH"

if [ -z "${TARGET_DIR:-}" ]; then
  echo "::error::out-dir-package needs a target-dir — without the RW target mount there is no host path to expose"
  exit 1
fi
# The package name is spliced into env-file lines; a strict crate-name
# pattern closes the newline vector before it reaches the file.
case "$OUT_DIR_PACKAGE" in
  *[!A-Za-z0-9_-]*)
    echo "::error::out-dir-package '$OUT_DIR_PACKAGE' is not a crate name"
    exit 1
    ;;
esac

# OFFLINE rides in EXTRA_ENV per call: it is not CARGO_* and would not
# forward itself (same reasoning as the main step).
EXTRA_ENV="$(printf '%s\n%s' "ARGS=pkgid -p $OUT_DIR_PACKAGE" "OFFLINE=${OFFLINE:-true}")"
export EXTRA_ENV
if ! spec="$(seal_run bash /cicd/cargo-docker.sh)"; then
  echo "::error::cargo pkgid failed for '$OUT_DIR_PACKAGE'"
  exit 1
fi

messages="$(mktemp)"
trap 'rm -f "$messages"' EXIT
EXTRA_ENV="$(printf '%s\n%s' "ARGS=build -p $OUT_DIR_PACKAGE $OUT_DIR_ARGS --message-format=json-diagnostic-rendered-ansi" "OFFLINE=${OFFLINE:-true}")"
export EXTRA_ENV
rc=0
seal_run bash /cicd/cargo-docker.sh > "$messages" || rc=$?
# The JSON stream claims stdout and carries the rendered compiler output;
# replay it to the log so warnings and build failures stay readable.
jq -rj 'select(.reason == "compiler-message") | .message.rendered // empty' "$messages" >&2 || true
if [ "$rc" -ne 0 ]; then
  echo "::error::the resolve build failed"
  exit "$rc"
fi

resolve_out_dir "$spec" "$messages"
seal_host_path "$OUT_DIR"

if [ ! -d "$HOST_PATH" ]; then
  echo "::error::translated OUT_DIR is not a host directory: $HOST_PATH"
  exit 1
fi
echo "OUT_DIR: $OUT_DIR -> $HOST_PATH"
echo "out-dir=$HOST_PATH" >> "$GITHUB_OUTPUT"
