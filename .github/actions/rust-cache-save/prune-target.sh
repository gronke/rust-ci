#!/usr/bin/env bash
# Prune target/ down to what a cache is worth keeping: DEPENDENCY artifacts.
# Workspace-member objects, final binaries, examples, incremental state and
# docs are rebuilt or relinked on any commit — caching them only grows the
# archive and the tar/zstd staging that can fill the runner disk at save time.
#
# DRY_RUN=1 prints what would go instead of removing it, for local runs.
set -euo pipefail

target="${RUST_CI_TARGET_DIR:?rust-cache did not export RUST_CI_TARGET_DIR}"
if [ ! -d "$target" ]; then
  echo "no $target directory; nothing to prune"
  exit 0
fi

remove() {
  if [ "${DRY_RUN:-}" = "1" ]; then
    printf 'would remove %s\n' "$@"
  else
    rm -rf -- "$@"
  fi
}

du -sh "$target" | sed 's/^/before: /'

# Workspace member names; their compiled artifacts use underscores.
members=$(cargo metadata --no-deps --format-version 1 | jq -r '.packages[].name' | tr '-' '_')

# Incremental state (defaulted off, but belt and braces), examples and docs,
# in the top-level and per-triple profile directories.
while IFS= read -r dir; do
  remove "$dir"
done < <(find "$target" -mindepth 1 -maxdepth 3 -type d \
  \( -name incremental -o -name examples -o -name doc \) 2>/dev/null)

# Every profile directory: target/<profile>/ and target/<triple>/<profile>/,
# recognized by their deps/ directory.
for dir in "$target"/*/ "$target"/*/*/; do
  [ -d "${dir}deps" ] || continue
  # Top-level files are final binaries and their dep-info: always relinked.
  while IFS= read -r file; do
    remove "$file"
  done < <(find "$dir" -maxdepth 1 -type f 2>/dev/null)
  for name in $members; do
    for pattern in "${dir}deps/${name}-"* "${dir}deps/lib${name}-"* \
      "${dir}.fingerprint/${name}-"* "${dir}build/${name}-"*; do
      [ -e "$pattern" ] || continue
      remove "$pattern"
    done
  done
done

du -sh "$target" | sed 's/^/after:  /'
