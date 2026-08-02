#!/usr/bin/env bash
# Retry a command whose failure came from the network rather than from the work
# it was asked to do. Source it (under `set -o pipefail`), then:
#
#   retry_transient docker build …
#
# A command that fails on its own terms — a bad Dockerfile, a compile error, a
# missing file — fails on its first attempt and keeps its exit status: only
# output naming a registry timeout, a reset connection or a rate limit is worth
# trying again. That distinction is the point; a blanket retry would triple the
# wall clock of every genuine failure.
#
# RETRY_ATTEMPTS (default 3) bounds the tries, RETRY_DELAY (default 5) the first
# pause; each further pause triples.

# Conditions a second attempt can plausibly survive.
_RETRY_TRANSIENT='i/o timeout|deadlineexceeded|timeout exceeded|context deadline|connection reset|connection refused|tls handshake|temporary failure|too many requests|toomanyrequests|unexpected eof|no such host|503 service|502 bad gateway'

retry_transient() {
  local attempt=1 max="${RETRY_ATTEMPTS:-3}" delay="${RETRY_DELAY:-5}" out status
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
  done
}
