#!/usr/bin/env bash
# Fragment helpers for the changelog action. A pull request may add
# changelog.d/<slug>.<section>.md — bullet lines only — instead of editing
# CHANGELOG.md's [Unreleased] section, so parallel branches never collide on
# the same region of one file. `check` reads the fragments as pending
# content; `cut` folds them into the released section and deletes them.
# Sourced by changelog.sh; expects $FRAGMENTS_DIR (defaults to changelog.d).
#
#   list_fragments        — validated, sorted fragment paths (empty when none)
#   fragment_bullets      — the fragments' bullet lines, concatenated
#   fold_fragments <ver>  — merge fragments into the [$ver] section of $CHANGELOG

FRAGMENTS_DIR="${INPUT_FRAGMENTS:-changelog.d}"

# Keep a Changelog's six sections in canonical order; the fragment filename's
# suffix names one of them, lowercased.
FRAGMENT_SECTIONS="added changed deprecated removed fixed security"

fragment_section_heading() {
  case "$1" in
    added) printf 'Added' ;;
    changed) printf 'Changed' ;;
    deprecated) printf 'Deprecated' ;;
    removed) printf 'Removed' ;;
    fixed) printf 'Fixed' ;;
    security) printf 'Security' ;;
    *) return 1 ;;
  esac
}

# Validated, sorted fragment paths, one per line. An unknown section suffix or
# a fragment without a single bullet fails loudly — a typo'd filename would
# otherwise survive the cut unnoticed, which is the silence the [Unreleased]
# region's conflicts at least forced a human past.
list_fragments() {
  [ -d "$FRAGMENTS_DIR" ] || return 0
  local f base section
  for f in "$FRAGMENTS_DIR"/*.md; do
    [ -e "$f" ] || return 0
    base="$(basename "$f" .md)"
    section="${base##*.}"
    if [ "$section" = "$base" ] || ! fragment_section_heading "$section" >/dev/null; then
      echo "::error::fragment $f needs a section suffix: .{added,changed,deprecated,removed,fixed,security}.md" >&2
      return 1
    fi
    if ! grep -q '^- ' "$f"; then
      echo "::error::fragment $f carries no '- ' bullet — fragments hold bullet lines only" >&2
      return 1
    fi
    printf '%s\n' "$f"
  done | LC_ALL=C sort
}

# Every fragment's content lines, in sorted-file order — the pending content
# the check greps (a **Breaking:** marker rides the bullet, as in the body).
# Blank lines are dropped; wrapped bullets and sub-items keep their text.
fragment_bullets() {
  local f
  for f in $(list_fragments); do
    grep -v '^[[:space:]]*$' "$f"
  done
}

# Whether the pending fragments declare feature content by filename — the
# pre-release version rule cannot read ### headings from bullet-only files.
fragments_have_feature_content() {
  list_fragments | grep -qE '\.(added|removed)\.md$'
}

# Create an empty [Unreleased] heading as the assembly point for a
# fragments-only cut: before the first released section, else before the
# link-definition block, else at the end of the file.
create_unreleased_heading() {
  awk '
    /^## / && !done { print "## [Unreleased]"; print ""; done=1 }
    /^\[[^]]+\]: / && !done { print "## [Unreleased]"; print ""; done=1 }
    { print }
    END { if (!done) { print ""; print "## [Unreleased]"; print "" } }
  ' "$CHANGELOG" > "$CHANGELOG.tmp"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
}

# Fold the fragments into the already-renamed [$VERSION] section of
# $CHANGELOG and remove the fragment files. Existing ### groups keep their
# order and gain the matching fragments' bullets; sections the section does
# not have yet are appended in canonical order.
fold_fragments() {
  local version="$1"
  local files
  files="$(list_fragments)"
  [ -n "$files" ] || return 0

  local tmpd
  tmpd="$(mktemp -d)"
  local f base section heading
  for f in $files; do
    base="$(basename "$f" .md)"
    section="${base##*.}"
    heading="$(fragment_section_heading "$section")"
    grep -v '^[[:space:]]*$' "$f" >> "$tmpd/$heading"
  done

  awk -v version="$version" -v fragdir="$tmpd" -v canon="$FRAGMENT_SECTIONS" \
    -f "$GITHUB_ACTION_PATH/../changelog/fold-fragments.awk" \
    "$CHANGELOG" > "$CHANGELOG.folded"
  mv "$CHANGELOG.folded" "$CHANGELOG"

  # shellcheck disable=SC2086
  rm -f $files
  rm -rf "$tmpd"
}
