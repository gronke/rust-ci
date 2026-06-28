#!/usr/bin/env bash
# Shared resolver/validator for a crate's declared MSRV, so the `msrv` action and
# build-image's `rust-version: msrv` sentinel accept exactly the same values. Source
# it, then call one of:
#
#   validate_rust_version "$v"        # 0 if numeric x[.y[.z]]; ::error:: + 1 otherwise
#   resolve_msrv_from_cargo <dir>     # read+validate <dir>/Cargo.toml → sets RESOLVED_MSRV
#
# A resolved (or overridden) version becomes a `rust:<v>` base tag and a buildx cache
# scope, so it is constrained to numeric major[.minor[.patch]] only — a crafted value
# (e.g. `latest; touch pwned`) can't smuggle a docker tag or shell flag downstream.
#
# Both functions write any `::error::` to stdout (so it surfaces as a step annotation)
# and report failure via a non-zero return; call them directly (not in `$(...)`) and
# read RESOLVED_MSRV, so the annotation is not swallowed by command substitution.

# Accept only major[.minor[.patch]] (e.g. 1, 1.95, 1.95.0).
validate_rust_version() {
  local v="$1"
  if [[ ! "$v" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "::error::rust-version: invalid '$v' (expected e.g. 1.95 or 1.95.0)"
    return 1
  fi
}

# Read the first `rust-version = "X"` from <dir>/Cargo.toml (the declared MSRV),
# validate it, and set RESOLVED_MSRV. ::error:: + non-zero on a missing manifest,
# a missing rust-version, or a non-numeric value.
resolve_msrv_from_cargo() {
  local dir="${1:-.}" manifest msrv
  manifest="$dir/Cargo.toml"
  if [ ! -f "$manifest" ]; then
    echo "::error::rust-version: no Cargo.toml in $dir"
    return 1
  fi
  msrv="$(grep -m1 '^rust-version' "$manifest" | sed 's/.*"\(.*\)".*/\1/' || true)"
  if [ -z "$msrv" ]; then
    echo "::error::rust-version: no rust-version in $manifest"
    return 1
  fi
  validate_rust_version "$msrv" || return 1
  # shellcheck disable=SC2034  # out-var: read by callers after sourcing (build-image, msrv)
  RESOLVED_MSRV="$msrv"
}
