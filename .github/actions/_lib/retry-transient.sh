#!/usr/bin/env bash
# Retry a command whose failure came from the network rather than from the work
# it was asked to do. Source it, then:
#
#   retry_transient docker build …
#
# Needs bash 4.4 for `local -`, which confines the pipefail this function
# depends on to the function itself.
#
# A command that fails on its own terms — a bad Dockerfile, a compile error, a
# missing file — fails on its first attempt and keeps its exit status: only
# output naming a registry timeout, a reset connection or a rate limit is worth
# trying again. That distinction is the point; a blanket retry would triple the
# wall clock of every genuine failure.
#
# RETRY_ATTEMPTS (default 5) bounds the tries, RETRY_DELAY (default 5) the first
# pause; each further pause triples up to RETRY_MAX_DELAY (default 60), so the
# default budget waits about two minutes in total. Registry degradation lasts
# minutes rather than seconds — a budget that only rides out a blip fails the
# job for the same reason having no retry did.

# Conditions a second attempt can plausibly survive.
_RETRY_TRANSIENT='i/o timeout|deadlineexceeded|timeout exceeded|context deadline|connection reset|connection refused|tls handshake|temporary failure|too many requests|toomanyrequests|unexpected eof|no such host|503 service|502 bad gateway'

retry_transient() {
  # Whether the command failed is read off a pipeline, so pipefail is not
  # optional: without it tee's success would report a failing command as a
  # success, and a red build would come back green. `local -` restores the
  # caller's options on return, so enforcing it here costs them nothing.
  local -
  set -o pipefail

  local attempt=1 max="${RETRY_ATTEMPTS:-5}" delay="${RETRY_DELAY:-5}" cap="${RETRY_MAX_DELAY:-60}" out status
  # A non-numeric bound would make the `-ge` test error out, the loop's exit
  # unreachable, and the job hang until the workflow timeout.
  case "$max" in
    '' | *[!0-9]*)
      echo "::error::RETRY_ATTEMPTS must be a whole number (got '${max}')"
      return 2
      ;;
  esac
  case "$delay" in
    '' | *[!0-9]*)
      echo "::error::RETRY_DELAY must be a whole number (got '${delay}')"
      return 2
      ;;
  esac
  case "$cap" in
    '' | *[!0-9]*)
      echo "::error::RETRY_MAX_DELAY must be a whole number (got '${cap}')"
      return 2
      ;;
  esac
  out="$(mktemp)"
  while :; do
    status=0
    "$@" 2>&1 | tee "$out" || status=$?
    if [ "$status" -eq 0 ]; then
      rm -f "$out"
      return 0
    fi
    if ! grep -qEi "$_RETRY_TRANSIENT" "$out"; then
      rm -f "$out"
      return "$status"
    fi
    if [ "$attempt" -ge "$max" ]; then
      echo "::error::still failing after ${attempt} attempts; the last one hit a transient network error"
      rm -f "$out"
      return "$status"
    fi
    echo "::warning::attempt ${attempt}/${max} hit a transient network error; retrying in ${delay}s"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 3))
    [ "$delay" -gt "$cap" ] && delay="$cap"
  done
}
