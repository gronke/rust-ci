#!/usr/bin/env bash
# Local lint: shellcheck, yamllint, actionlint (through Docker), jq on the ruleset JSON and the em-dash check.
# The repository has no lint CI; run this before opening a pull request.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
rc=0
find .github -name '*.sh' -print0 | xargs -0 shellcheck -x -P SCRIPTDIR -S style || rc=1
yamllint .github || rc=1
docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:1.7.12 -no-color || rc=1
for f in .github/rulesets/*.json; do jq empty "$f" || { echo "invalid JSON: $f"; rc=1; }; done
if grep -rn --exclude-dir=.git $'\xe2\x80\x94' --include='*.md' --include='*.yml' --include='*.sh' --include='*.json' --include='*.toml' .; then
  echo "em-dashes found; use a period, colon or comma"
  rc=1
fi
exit $rc
