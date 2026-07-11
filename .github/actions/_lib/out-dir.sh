#!/usr/bin/env bash
# Shared resolver for a build script's OUT_DIR, so every build-producing
# action reads cargo's JSON messages the same way. Source it, then call:
#
#   resolve_out_dir <package-id-spec> <messages-file>   # sets OUT_DIR
#
# The spec is `cargo pkgid` output; the messages file is the stdout of a
# `cargo build --message-format=json` run in the same workspace (and, for a
# container build, under the same mount layout — both sides then carry the
# same path form, so host paths never enter the comparison). Every build
# script in the graph emits a build-script-executed message; exact
# package_id equality picks the requested one (cargo ≥1.77 prints the same
# PackageIdSpec from `cargo pkgid` and in the messages). Zero matches or
# more than one distinct directory fail loudly.
#
# Any `::error::` goes to stdout (so it surfaces as a step annotation) and
# failure is a non-zero return; call it directly (not in `$(...)`), so the
# annotation is not swallowed by command substitution.
resolve_out_dir() {
  local spec="$1" messages="$2" dirs
  if ! dirs="$(jq -r --arg spec "$spec" '
    select(.reason == "build-script-executed")
    | select(.package_id == $spec)
    | .out_dir' "$messages" | sort -u)"; then
    echo "::error::failed to parse the cargo message stream"
    return 1
  fi
  if [ -z "$dirs" ]; then
    echo "::error::no build-script OUT_DIR for '$spec' (no build.rs, or the cargo in use predates the 1.77 package-id format)"
    return 1
  fi
  if [ "$(printf '%s\n' "$dirs" | wc -l)" -gt 1 ]; then
    echo "::error::ambiguous build-script OUT_DIR for '$spec':"
    printf '%s\n' "$dirs"
    return 1
  fi
  # shellcheck disable=SC2034  # out-var: read by callers after sourcing
  OUT_DIR="$dirs"
}
