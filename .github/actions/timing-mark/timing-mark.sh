#!/usr/bin/env bash
# Record a stage boundary. Inputs arrive as env vars from action.yml:
#   STAGE   name of the stage that begins here
set -euo pipefail

# shellcheck source=../_lib/timing.sh disable=SC1091
source "$GITHUB_ACTION_PATH/../_lib/timing.sh"

timing_mark "$STAGE"
