#!/usr/bin/env bash
# Keep a "Keep a Changelog" CHANGELOG.md coherent with the crate's declared
# version. Inputs arrive as env vars from action.yml; cargo and git run in the
# step's working-directory.
#   INPUT_MODE              "check" (PR gate), "cut" (release the section), or "notes"
#                           (render a released section as plain text for a tag/release)
#   INPUT_PACKAGE           package name (required for a multi-member workspace)
#   INPUT_CHANGELOG         changelog path, relative to the working directory
#   INPUT_VERSION           the version, any mode (else resolved from Cargo.toml; a repo
#                           without a crate needs it for cut, and check degrades gracefully)
#   INPUT_OUT               notes: file the rendered notes are written to (default release-notes.md)
#   INPUT_TITLE             notes: optional subject line led before the section (e.g. a git tag subject)
#   INPUT_BASELINE_VERSION  check: version the crate must exceed (else the greatest release
#                           tag, pre-releases included, by SemVer precedence)
#   INPUT_DATE              cut: date stamped on the released section (else today, UTC)
set -euo pipefail

source "$GITHUB_ACTION_PATH/../_lib/crate-version.sh"
source "$GITHUB_ACTION_PATH/../_lib/changelog-version.sh"
source "$GITHUB_ACTION_PATH/../_lib/semver.sh"

CHANGELOG="${INPUT_CHANGELOG:-CHANGELOG.md}"
if [ ! -f "$CHANGELOG" ]; then
  echo "::error::no changelog at $CHANGELOG"
  exit 1
fi

# The version ladder: the explicit input, else Cargo.toml. A repository
# without either still checks (section/tag coherence below) but cannot cut
# or render a version it does not know.
VERSION="${INPUT_VERSION:-}"
if [ -z "$VERSION" ] && [ -f Cargo.toml ]; then
  resolve_crate "${INPUT_PACKAGE:-}"
  VERSION="$CRATE_VERSION"
fi

# The [Unreleased] section body: everything between its heading and the next
# section heading or the link-definition block.
unreleased_body() {
  awk '/^## \[Unreleased\]/{grab=1; next} /^## /{grab=0} /^\[[^]]+\]: /{grab=0} grab' "$CHANGELOG"
}

# SemVer precedence (semver_gt from _lib) decides order; the numeric components
# feed the breaking-bump rule (a prerelease suffix on a component is ignored there).
ver_part() {
  local part
  part="$(printf '%s' "$1" | cut -d. -f"$2" | grep -o '^[0-9]*' || true)"
  printf '%s' "${part:-0}"
}

case "${INPUT_MODE:-}" in
  check)
    if ! grep -q '^## \[Unreleased\]' "$CHANGELOG"; then
      echo "✓ no [Unreleased] section in $CHANGELOG; nothing to check"
      exit 0
    fi
    BODY="$(unreleased_body)"
    if [ -z "$(printf '%s' "$BODY" | tr -d '[:space:]')" ]; then
      echo "✓ [Unreleased] is empty; nothing to check"
      exit 0
    fi
    if [ -z "$VERSION" ]; then
      # No crate and no version input: the bump rule needs the next version,
      # which only exists at dispatch time here. Check what the changelog
      # itself declares instead — the newest released section must be tagged
      # (a warning when not: a cut may be in flight before its merge-back).
      resolve_changelog_version "$CHANGELOG"
      if [ -z "$CHANGELOG_LATEST" ]; then
        echo "✓ [Unreleased] carries entries and nothing is released yet; the version arrives at cut time"
      elif [ -n "$(git tag -l "v${CHANGELOG_LATEST}" 2>/dev/null)" ]; then
        echo "✓ [Unreleased] carries entries and the newest released section (v${CHANGELOG_LATEST}) is tagged; the version arrives at cut time"
      else
        echo "::warning::the newest released section (${CHANGELOG_LATEST}) has no v${CHANGELOG_LATEST} tag — a release may be in flight, or was never finished"
      fi
      exit 0
    fi
    if ! semver_valid "$VERSION"; then
      echo "::error::the declared version ($VERSION) is not a MAJOR.MINOR.PATCH[-prerelease] version"
      exit 1
    fi
    BASE="${INPUT_BASELINE_VERSION:-}"
    if [ -z "$BASE" ]; then
      # The greatest release tag by SemVer precedence, pre-release tags included —
      # a v1.0.0 final outranks its v1.0.0-rcN candidates, unlike `sort -V`.
      for TAG in $(git tag -l 'v*' 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$' || true); do
        TAG="${TAG#v}"
        if [ -z "$BASE" ] || semver_gt "$TAG" "$BASE"; then
          BASE="$TAG"
        fi
      done
    fi
    if [ -z "$BASE" ]; then
      BASE="0.0.0"
      echo "::notice::no baseline-version input and no release tag in the checkout; using 0.0.0"
    fi
    if ! semver_gt "$VERSION" "$BASE"; then
      echo "::error::[Unreleased] carries entries, but the crate version ($VERSION) does not exceed the last release ($BASE) — bump the version in Cargo.toml"
      exit 1
    fi
    # A release-candidate version is for stabilizing exactly that release: feature
    # content resets the version out of rc-space.
    if [ -n "$(semver_prerelease "$VERSION")" ]; then
      if printf '%s' "$BODY" | grep -Eq '^### (Added|Removed)|\*\*Breaking'; then
        echo "::error::the crate version ($VERSION) is a pre-release, but [Unreleased] carries feature content (### Added, ### Removed, or a **Breaking entry) — feature work resets the version to the next regular release"
        exit 1
      fi
    fi
    if printf '%s' "$BODY" | grep -q '\*\*Breaking'; then
      base_major="$(ver_part "$BASE" 1)"; base_minor="$(ver_part "$BASE" 2)"
      major="$(ver_part "$VERSION" 1)"; minor="$(ver_part "$VERSION" 2)"
      bumped=false
      if [ "$major" -gt "$base_major" ]; then
        bumped=true
      elif [ "$major" -eq "$base_major" ] && [ "$major" -eq 0 ] && [ "$minor" -gt "$base_minor" ]; then
        bumped=true
      fi
      if [ "$bumped" != "true" ]; then
        echo "::error::[Unreleased] marks a breaking change; $VERSION over $BASE needs at least a minor bump (0.x) or a major bump (1.x and up)"
        exit 1
      fi
    fi
    echo "✓ changelog and version are coherent ($VERSION over $BASE)"
    ;;

  cut)
    if [ -z "$VERSION" ]; then
      echo "::error::cut needs a version — none given and no Cargo.toml declares one"
      exit 1
    fi
    HEADINGS="$(grep -c '^## \[Unreleased\]' "$CHANGELOG" || true)"
    if [ "$HEADINGS" -eq 0 ]; then
      echo "::error::no [Unreleased] section to cut in $CHANGELOG"
      exit 1
    fi
    if [ "$HEADINGS" -ne 1 ]; then
      echo "::error::$CHANGELOG carries $HEADINGS [Unreleased] headings; expected exactly one"
      exit 1
    fi
    BODY="$(unreleased_body)"
    if [ -z "$(printf '%s' "$BODY" | tr -d '[:space:]')" ]; then
      echo "::error::[Unreleased] is empty; nothing to release"
      exit 1
    fi
    if grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
      echo "::error::$CHANGELOG already carries a [$VERSION] section"
      exit 1
    fi
    DATE="${INPUT_DATE:-$(date -u +%F)}"
    sed -i "s|^## \[Unreleased\].*|## [$VERSION] - $DATE|" "$CHANGELOG"
    # Link block: the [Unreleased] compare link becomes the released one.
    if grep -qE '^\[Unreleased\]: ' "$CHANGELOG"; then
      LINK="$(grep -E '^\[Unreleased\]: ' "$CHANGELOG" | head -n1)"
      if [[ "$LINK" =~ ^\[Unreleased\]:\ (.*)/compare/(.*)\.\.\.HEAD$ ]]; then
        base="${BASH_REMATCH[1]}"
        prev="${BASH_REMATCH[2]}"
        sed -i "s|^\[Unreleased\]: .*|[$VERSION]: $base/compare/$prev...v$VERSION|" "$CHANGELOG"
      else
        echo "::error::the [Unreleased] link is not a .../compare/<prev>...HEAD URL; fix or drop it"
        exit 1
      fi
    else
      echo "::notice::no [Unreleased] link line; only the heading was rewritten"
    fi
    if [ -n "${GITHUB_ENV:-}" ]; then
      echo "CHANGELOG_VERSION=$VERSION" >> "$GITHUB_ENV"
    fi
    echo "✓ cut [$VERSION] - $DATE from [Unreleased]"
    ;;

  notes)
    if [ -z "$VERSION" ]; then
      # The newest released section is what a release branch renders.
      resolve_changelog_version "$CHANGELOG"
      VERSION="$CHANGELOG_LATEST"
      if [ -z "$VERSION" ]; then
        echo "::error::notes needs a version — none given, no Cargo.toml, and no released section"
        exit 1
      fi
    fi
    OUT="${INPUT_OUT:-release-notes.md}"
    if ! grep -q "^## \[$VERSION\]" "$CHANGELOG"; then
      echo "::error::no [$VERSION] section in $CHANGELOG"
      exit 1
    fi
    # The [VERSION] section body — heading and link block excluded, like
    # unreleased_body — de-Markdowned for a plain-text tag message or release body:
    # ** and backticks dropped, ### Group -> Group:, single * / _ and the wrapping
    # left alone; the trailing awk trims leading and trailing blank lines.
    SECTION="$(awk -v h="## [$VERSION]" 'index($0, h) == 1 {grab=1; next} /^## /{grab=0} /^\[[^]]+\]: /{grab=0} grab' "$CHANGELOG" \
      | sed -E 's/`//g; s/\*\*//g; s/^### (.+)/\1:/' \
      | awk 'NF && !first {first=NR} NF{last=NR} {line[NR]=$0} END{for (i = first; i <= last; i++) print line[i]}')"
    if [ -z "${SECTION//[[:space:]]/}" ]; then
      echo "::error::rendered notes for $VERSION are empty"
      exit 1
    fi
    # An optional title leads as the first line (a git tag subject), then a blank
    # line, then the section — so the section's first group heading is not the subject.
    if [ -n "${INPUT_TITLE:-}" ]; then
      printf '%s\n\n%s\n' "$INPUT_TITLE" "$SECTION" > "$OUT"
    else
      printf '%s\n' "$SECTION" > "$OUT"
    fi
    echo "::group::rendered notes → $OUT"
    cat "$OUT"
    echo "::endgroup::"
    ;;

  *)
    echo "::error::mode must be 'check', 'cut', or 'notes' (got '${INPUT_MODE:-}')"
    exit 1
    ;;
esac
