#!/usr/bin/env bash
# Shared probe for the repository's tag-signature policy. Source it, then call:
#
#   signature_rule_covers_ref <ref>   # sets SIGNATURE_RULE_VERDICT
#
# SIGNATURE_RULE_VERDICT is "true" only when an active required_signatures
# ruleset's conditions match the given ref (e.g. refs/tags/v1.4.0), so a rule
# scoped to attestation companions does not mark plain versions as
# signature-enforced. It is "unknown" whenever the policy cannot be
# established: the ruleset listing or a ruleset's detail is unreadable, or a
# condition pattern is one this probe cannot faithfully evaluate. Callers treat
# unknown as the conservative case — a signature rule that might cover the ref
# must never read as absent.
#
# Call it directly, never in `$(...)`: a subshell would discard the ruleset
# cache, so every question would pay for its own API reads.

_TAG_RULESET_DOCS=""   # cached documents, one JSON object per line
_TAG_RULESET_STATUS="" # "ok" | "fail"; empty until the first read

# Every active tag ruleset, in full, read once per process: the mode
# resolution and the collision check ask the same question.
_load_tag_rulesets() {
  if [ -z "$_TAG_RULESET_STATUS" ]; then
    local ids id raw docs=""
    if ids="$(gh api "repos/${GITHUB_REPOSITORY}/rulesets" \
      --jq '.[] | select(.target == "tag" and .enforcement == "active") | .id' 2>/dev/null)"; then
      _TAG_RULESET_STATUS="ok"
      for id in $ids; do
        # gh's own status decides: a jq pipeline would mask a failed read as
        # an empty document, which reads as "no signature rule".
        if raw="$(gh api "repos/${GITHUB_REPOSITORY}/rulesets/${id}" 2>/dev/null)"; then
          docs="${docs}$(printf '%s' "$raw" | jq -c .)"$'\n'
        else
          _TAG_RULESET_STATUS="fail"
          break
        fi
      done
      _TAG_RULESET_DOCS="$docs"
    else
      _TAG_RULESET_STATUS="fail"
    fi
  fi
  [ "$_TAG_RULESET_STATUS" = "ok" ]
}

# GitHub matches ruleset conditions with fnmatch; shell globs agree for the
# plain patterns this flow uses — literals, `*`, `?`, and simple `[...]`
# classes. Anything else (an escape, a negated class, an unterminated class)
# is a pattern this probe cannot claim to evaluate, and its ruleset resolves
# to unknown rather than "does not match".
_pattern_confident() {
  case "$1" in
    *'\'* | *'[!'* | *'[^'*) return 1 ;;
  esac
  local after_open="${1#*[}"
  if [ "$after_open" != "$1" ] && [ "$after_open" = "${after_open#*]}" ]; then
    return 1 # an opening bracket with no close
  fi
  return 0
}

signature_rule_covers_ref() {
  local ref="$1" doc pat matched excluded unsure verdict="false"
  SIGNATURE_RULE_VERDICT="unknown"
  _load_tag_rulesets || return 0

  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    printf '%s' "$doc" | jq -e 'any(.rules[]?; .type == "required_signatures")' >/dev/null || continue

    matched="" unsure=""
    while IFS= read -r pat; do
      if [ "$pat" = "~ALL" ]; then
        matched=1
        continue
      fi
      _pattern_confident "$pat" || {
        unsure=1
        continue
      }
      # shellcheck disable=SC2254  # the pattern must glob
      case "$ref" in $pat) matched=1 ;; esac
    done < <(printf '%s' "$doc" | jq -r '.conditions.ref_name.include[]?')
    if [ -z "$matched" ]; then
      # A pattern we could not evaluate may well have matched.
      [ -n "$unsure" ] && verdict="unknown"
      continue
    fi

    excluded=""
    while IFS= read -r pat; do
      _pattern_confident "$pat" || {
        unsure=1
        continue
      }
      # shellcheck disable=SC2254
      case "$ref" in $pat) excluded=1 ;; esac
    done < <(printf '%s' "$doc" | jq -r '.conditions.ref_name.exclude[]?')
    [ -n "$excluded" ] && continue

    # Included and not excluded — unless an unevaluable exclusion could lift it.
    if [ -n "$unsure" ]; then
      verdict="unknown"
      continue
    fi
    SIGNATURE_RULE_VERDICT="true"
    return 0
  done <<<"$_TAG_RULESET_DOCS"

  SIGNATURE_RULE_VERDICT="$verdict"
}
