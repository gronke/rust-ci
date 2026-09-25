#!/usr/bin/env bash
# Whether a tool is already installed at an exact version. Source it, then:
#
#   tool_present <binary> <version>        the binary exists and reports that version
#   tool_found <bin> <version> <bin-dir>   prints the path of that binary, if the one later steps run reports it
#
# "Reports" means the first version-shaped token of `<binary> --version`, the
# convention cargo tools follow ("cargo-nextest 0.9.146 (…)"). tool_found
# resolves <bin> the way a later step does, with <bin-dir> ahead of PATH,
# where a runner image keeps the tools it bakes: a binary in <bin-dir> shadows
# one on PATH, so it is the one that has to report the version. Both run the
# binary, so they serve host mode alone; a sealed container's cache is never
# executed on the runner.

tool_present() {
  local binary="$1" version="$2" have
  [ -x "$binary" ] || return 1
  have=$("$binary" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?' | head -n 1) || true
  [ -n "$have" ] && [ "$have" = "$version" ]
}

tool_found() {
  local bin="$1" version="$2" bin_dir="$3" candidate
  # A subshell, so the PATH it sets (and the command hash it resets) stays there.
  candidate=$(
    PATH="$bin_dir:$PATH"
    command -v "$bin"
  ) || return 1
  tool_present "$candidate" "$version" || return 1
  echo "$candidate"
}
