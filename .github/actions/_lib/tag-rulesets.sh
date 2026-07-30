#!/usr/bin/env bash
# Shared probe for the repository's tag-signature policy. Source it, then call:
#
#   signature_tag_ruleset_active   # prints "true", "false", or "unknown"
#
# "true" when an active tag ruleset carries required_signatures, "false" when
# none does, "unknown" when the token cannot read the rulesets. The probe is
# deliberately coarse — it does not pattern-match the ruleset's conditions —
# matching the alignment warning in require-signed-tag: the presence of any
# active signature rule marks the repository as signature-enforcing.
signature_tag_ruleset_active() {
  local ids id
  if ! ids="$(gh api "repos/${GITHUB_REPOSITORY}/rulesets" \
    --jq '.[] | select(.target == "tag" and .enforcement == "active") | .id' 2>/dev/null)"; then
    printf 'unknown'
    return 0
  fi
  for id in $ids; do
    if gh api "repos/${GITHUB_REPOSITORY}/rulesets/${id}" \
      --jq '.rules[].type' 2>/dev/null | grep -qx 'required_signatures'; then
      printf 'true'
      return 0
    fi
  done
  printf 'false'
}
