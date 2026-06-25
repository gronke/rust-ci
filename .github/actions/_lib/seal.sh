#!/usr/bin/env bash
# Shared sealed-runner for the Docker actions. Source it, then call `seal_run`:
#
#   source "$GITHUB_ACTION_PATH/../_lib/seal.sh"
#   seal_run bash /cicd/<script>.sh        # or: seal_run bash -c '<inline>'
#
# It owns the single hardened `docker run` so the containment policy lives in one
# place: non-root (`--user`), all Linux capabilities dropped (`--cap-drop=ALL`),
# no privilege escalation (`--security-opt=no-new-privileges`), the repo mounted
# read-only, and — when OFFLINE=true — sealed with `--network=none` so a build
# (and the dependency build.rs / proc-macros it runs) cannot reach the network.
# Run cargo-fetch first to warm the cache for the sealed (offline) path.
#
# Config is read from the environment (an action sets these before calling):
#   IMAGE        (required) the CI image to run
#   CARGO_CACHE  (required) host dir for CARGO_HOME (registry/git cache), mounted RW
#   OFFLINE      "true" → --network=none (sealed); anything else → networked
#   TARGET_DIR   if non-empty: mount it RW at /work/target + set CARGO_TARGET_DIR
#   CICD_DIR     if non-empty: mount it RO at /cicd (so `bash /cicd/<script>` resolves)
#   ENV_INCLUDE / ENV_EXCLUDE   POSIX-ERE name filters for env forwarding (exclusion wins)
#   INPUT_ENV    extra literal KEY=VALUE lines (the action's `env` input), forwarded verbatim
#   EXTRA_ENV    extra literal KEY=VALUE lines the action itself injects (e.g. ARGS, a masked token)
# Args ("$@"): the command to exec inside the container.
#
# The owner vars (CARGO_HOME / RUSTUP_HOME / CARGO_TARGET_DIR) are pinned as explicit
# `-e` AFTER --env-file (last-wins), so no env-include/-exclude tinkering can redirect
# the mounted cache or target.

seal_run() {
  : "${IMAGE:?seal_run: IMAGE required}" "${CARGO_CACHE:?seal_run: CARGO_CACHE required}"
  mkdir -p "$CARGO_CACHE"

  local net=""
  [ "${OFFLINE:-}" = "true" ] && net="--network=none"

  local target_args=()
  if [ -n "${TARGET_DIR:-}" ]; then
    mkdir -p "$TARGET_DIR"
    target_args=(-e CARGO_TARGET_DIR=/work/target -v "$PWD/$TARGET_DIR:/work/target")
  fi

  local cicd_args=()
  [ -n "${CICD_DIR:-}" ] && cicd_args=(-v "$CICD_DIR:/cicd:ro")

  # Forward env: keep names matching ENV_INCLUDE (default CARGO_.*), drop ENV_EXCLUDE
  # (exclusion wins), then append the literal `env` input and any action-injected EXTRA_ENV.
  local ef
  ef="$(mktemp)"
  env | awk -v inc="${ENV_INCLUDE:-}" -v exc="${ENV_EXCLUDE:-}" '
    { name = $0; sub(/=.*/, "", name) }
    inc != "" && name !~ "^(" inc ")$" { next }
    exc != "" && name ~  "^(" exc ")$" { next }
    { print }
  ' > "$ef"
  [ -n "${INPUT_ENV:-}" ] && printf '%s\n' "$INPUT_ENV" >> "$ef"
  [ -n "${EXTRA_ENV:-}" ] && printf '%s\n' "$EXTRA_ENV" >> "$ef"

  local rc=0
  # shellcheck disable=SC2086  # $net is intentionally word-split (flag or empty)
  docker run --rm $net \
    --security-opt=no-new-privileges --cap-drop=ALL \
    --env-file "$ef" \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e CARGO_HOME=/cache/cargo \
    -e RUSTUP_HOME=/usr/local/rustup \
    "${target_args[@]}" \
    -v "$PWD:/work:ro" \
    -v "$PWD/$CARGO_CACHE:/cache/cargo" \
    "${cicd_args[@]}" \
    -w /work \
    "$IMAGE" "$@" || rc=$?
  rm -f "$ef"
  return "$rc"
}
