#!/usr/bin/env bash
# Build a package and resolve its build script's OUT_DIR. Inputs arrive as
# env vars from action.yml; cargo runs in the step's working-directory.
#   PACKAGE   package whose build script to resolve (empty: the workspace's
#             sole or root package, cargo pkgid's own resolution)
#   PROFILE   cargo profile (empty: dev)
#   ARGS      extra cargo build args
set -euo pipefail

# The exact package id keys the message lookup below; resolving it first
# fails fast on an unknown or ambiguous package.
# shellcheck disable=SC2086  # the PACKAGE expansion is intentionally split
if ! spec="$(cargo pkgid ${PACKAGE:+-p "$PACKAGE"})"; then
  echo "::error::cargo pkgid failed for '${PACKAGE:-the workspace root}'"
  exit 1
fi

messages="$(mktemp)"
trap 'rm -f "$messages"' EXIT
rc=0
# shellcheck disable=SC2086  # ARGS is intentionally split
cargo build ${PACKAGE:+-p "$PACKAGE"} ${PROFILE:+--profile "$PROFILE"} $ARGS \
  --message-format=json-diagnostic-rendered-ansi > "$messages" || rc=$?
# The JSON stream claims stdout and carries the rendered compiler output;
# replay it to the log so warnings and build failures stay readable.
jq -rj 'select(.reason == "compiler-message") | .message.rendered // empty' "$messages" >&2 || true
if [ "$rc" -ne 0 ]; then
  echo "::error::cargo build failed for '${PACKAGE:-the workspace root}'"
  exit "$rc"
fi

# shellcheck source=../_lib/out-dir.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/out-dir.sh"
resolve_out_dir "$spec" "$messages"

if [ ! -d "$OUT_DIR" ]; then
  echo "::error::resolved OUT_DIR is not a directory: $OUT_DIR"
  exit 1
fi
echo "OUT_DIR: $OUT_DIR"
echo "out-dir=$OUT_DIR" >> "$GITHUB_OUTPUT"
