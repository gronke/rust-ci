#!/usr/bin/env bash
# Shared SemVer precedence for the release actions, so pre-release versions
# order the way cargo and the spec order them (1.0.0-rc1 < 1.0.0 — the
# opposite of `sort -V`). Source it, then call:
#
#   semver_valid <version>       # 0 when the grammar is accepted
#   semver_prerelease <version>  # prints the pre-release part, empty when none
#   semver_gt <a> <b>            # 0 when a > b by SemVer §11 precedence
#
# Accepted grammar: MAJOR.MINOR.PATCH with an optional -PRERELEASE of
# dot-separated [0-9A-Za-z-] identifiers; build metadata (+…) is accepted and
# ignored for precedence, as the spec says. Precedence: the numeric core
# first; a pre-release orders below its release; pre-release identifiers
# compare numerically when both are numeric, byte-lexically otherwise, and a
# numeric identifier orders below an alphanumeric one; a shorter identifier
# list orders below a longer one sharing its prefix. Note the spec's lexical
# rule means `rc9 > rc10` — number your candidates `-rc.9`, `-rc.10` (numeric
# identifiers) when double digits are in reach.
#
# `semver_gt` returns 2 (with an `::error::` on stdout) for a version outside
# the grammar; call it directly (not in `$(...)`), so annotations surface.

semver_valid() {
  printf '%s' "${1%%+*}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
}

semver_prerelease() {
  local v="${1%%+*}" rest
  rest="${v#*-}"
  if [ "$rest" = "$v" ]; then
    printf ''
  else
    printf '%s' "$rest"
  fi
}

# Prints -1, 0, or 1. Both arguments must already satisfy semver_valid.
_semver_cmp() {
  local a="${1%%+*}" b="${2%%+*}"
  local a_core="${a%%-*}" b_core="${b%%-*}"
  local -a A B
  local i x y
  IFS='.' read -r -a A <<<"$a_core"
  IFS='.' read -r -a B <<<"$b_core"
  for i in 0 1 2; do
    if [ "${A[$i]}" -gt "${B[$i]}" ]; then printf '1'; return; fi
    if [ "${A[$i]}" -lt "${B[$i]}" ]; then printf '%s' '-1'; return; fi
  done
  local ap bp
  ap="$(semver_prerelease "$a")"
  bp="$(semver_prerelease "$b")"
  if [ -z "$ap" ] && [ -z "$bp" ]; then printf '0'; return; fi
  if [ -z "$ap" ]; then printf '1'; return; fi # a release outranks its pre-releases
  if [ -z "$bp" ]; then printf '%s' '-1'; return; fi
  IFS='.' read -r -a A <<<"$ap"
  IFS='.' read -r -a B <<<"$bp"
  for ((i = 0; i < ${#A[@]} || i < ${#B[@]}; i++)); do
    x="${A[$i]:-}"
    y="${B[$i]:-}"
    if [ -z "$x" ]; then printf '%s' '-1'; return; fi # shorter prefix orders lower
    if [ -z "$y" ]; then printf '1'; return; fi
    if printf '%s' "$x" | grep -Eq '^[0-9]+$' && printf '%s' "$y" | grep -Eq '^[0-9]+$'; then
      if [ "$x" -gt "$y" ]; then printf '1'; return; fi
      if [ "$x" -lt "$y" ]; then printf '%s' '-1'; return; fi
    elif printf '%s' "$x" | grep -Eq '^[0-9]+$'; then
      printf '%s' '-1'; return # numeric orders below alphanumeric
    elif printf '%s' "$y" | grep -Eq '^[0-9]+$'; then
      printf '1'; return
    else
      if [ "$x" \> "$y" ]; then printf '1'; return; fi
      if [ "$x" \< "$y" ]; then printf '%s' '-1'; return; fi
    fi
  done
  printf '0'
}

semver_gt() {
  local v
  for v in "$1" "$2"; do
    if ! semver_valid "$v"; then
      echo "::error::'$v' is not a MAJOR.MINOR.PATCH[-prerelease] version"
      return 2
    fi
  done
  [ "$(_semver_cmp "$1" "$2")" = "1" ]
}
