#!/usr/bin/env bash
# Shared probes for the repository's tag-signature policy. Source it, then call:
#
#   signature_tag_ruleset_active      # prints "true", "false", or "unknown"
#   signature_rule_covers_ref <ref>   # prints "true", "false", or "unknown"
#
# signature_tag_ruleset_active is the coarse repository-wide signal: "true"
# when any active tag ruleset carries required_signatures.
# signature_rule_covers_ref answers for one concrete ref (e.g.
# refs/tags/v1.4.0): "true" only when an active required_signatures ruleset's
# conditions match it — a rule scoped to attestation companions
# (refs/tags/v*-sig) does not mark plain versions as signature-enforced.
# Both print "unknown" when the ruleset listing or any ruleset's detail cannot
# be read; callers treat unknown as the conservative case.
#
# Condition matching approximates GitHub's fnmatch with shell globs (~ALL
# matches everything) — exact for the slash-free tag names this flow uses.

_tag_ruleset_docs() { # one JSON document per active tag ruleset; fails when any read fails
  local ids id
  ids="$(gh api "repos/${GITHUB_REPOSITORY}/rulesets" \
    --jq '.[] | select(.target == "tag" and .enforcement == "active") | .id' 2>/dev/null)" || return 1
  for id in $ids; do
    gh api "repos/${GITHUB_REPOSITORY}/rulesets/${id}" 2>/dev/null || return 1
  done
}

signature_tag_ruleset_active() {
  local docs
  docs="$(_tag_ruleset_docs)" || {
    printf 'unknown'
    return 0
  }
  if [ "$(printf '%s' "$docs" | jq -rs 'any(.[]; any(.rules[]?; .type == "required_signatures"))')" = "true" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

signature_rule_covers_ref() {
  local ref="$1" docs doc pat matched excluded
  docs="$(_tag_ruleset_docs)" || {
    printf 'unknown'
    return 0
  }
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    printf '%s' "$doc" | jq -e 'any(.rules[]?; .type == "required_signatures")' >/dev/null || continue
    matched=""
    while IFS= read -r pat; do
      [ "$pat" = "~ALL" ] && pat="*"
      # shellcheck disable=SC2254  # the pattern must glob
      case "$ref" in $pat) matched=1 ;; esac
    done < <(printf '%s' "$doc" | jq -r '.conditions.ref_name.include[]?')
    [ -n "$matched" ] || continue
    excluded=""
    while IFS= read -r pat; do
      # shellcheck disable=SC2254
      case "$ref" in $pat) excluded=1 ;; esac
    done < <(printf '%s' "$doc" | jq -r '.conditions.ref_name.exclude[]?')
    [ -n "$excluded" ] && continue
    printf 'true'
    return 0
  done < <(printf '%s' "$docs" | jq -c '.')
  printf 'false'
}
