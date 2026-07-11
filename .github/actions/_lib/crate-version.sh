#!/usr/bin/env bash
# Shared resolver for a crate's identity, so every release action reads the
# declared version the same way. Source it, then call:
#
#   resolve_crate <package-or-empty>   # sets CRATE_NAME, CRATE_VERSION, CRATE_PUBLISHABLE
#
# cargo runs in the caller's working directory. An empty package selects the
# sole member of a single-member workspace; a larger workspace needs the name.
# CRATE_PUBLISHABLE is "true" when the manifest allows publishing to crates.io
# (`publish` unset, or an array containing "crates-io").
#
# Any `::error::` goes to stdout (so it surfaces as a step annotation) and
# failure is a non-zero return; call it directly (not in `$(...)`), so the
# annotation is not swallowed by command substitution.
resolve_crate() {
  local package="${1:-}" meta summary
  if ! meta=$(cargo metadata --no-deps --format-version 1); then
    echo "::error::cargo metadata failed"
    return 1
  fi
  if ! summary=$(printf '%s' "$meta" | jq -r --arg name "$package" '
    (if $name == "" then
       (if (.packages | length) == 1 then .packages[0]
        else error("multiple packages; set the package input") end)
     else (.packages[] | select(.name == $name))
     end) as $p
    | ($p.publish == null
       or (($p.publish | type) == "array" and ($p.publish | any(. == "crates-io")))) as $pub
    | "\($p.name)\t\($p.version)\t\($pub)"
  '); then
    echo "::error::package selection failed (a multi-member workspace needs the package input)"
    return 1
  fi
  # shellcheck disable=SC2034  # out-vars: read by callers after sourcing
  IFS=$'\t' read -r CRATE_NAME CRATE_VERSION CRATE_PUBLISHABLE <<< "$summary"
  if [ -z "${CRATE_NAME:-}" ]; then
    echo "::error::package '${package}' not found in cargo metadata"
    return 1
  fi
}
