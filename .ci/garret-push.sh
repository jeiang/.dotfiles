#!/usr/bin/env bash
# Push store paths to the garret cache, retrying on transient failures.
# Replaces .ci/attic-login-push.sh + .ci/attic-push-retry.sh (docs/adr/0013):
# there is no login step any more, because the garret client mints its own
# token from the GitHub Actions OIDC provider (garret-client src/auth.rs
# `bearer_token`).
#
# Pushes are idempotent server-side -- already-present paths answer
# `{"status":"exists"}` with no body transfer (garret spec 01) -- so a retry
# only re-uploads whatever failed mid-transfer.
#
# A cache push is an optimization, not a build product: exhausting all
# attempts emits a workflow warning and exits 0 so cache outages cannot
# fail CI. Set GARRET_PUSH_STRICT=1 to restore hard failure.
#
# Each attempt runs under a watchdog. The client has its own per-request
# retry budget, but a black-holed connection can still stall a streaming
# PUT indefinitely; the watchdog is what bounds the whole attempt. Tune
# with GARRET_PUSH_TIMEOUT (seconds).
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <store-path>..." >&2
  exit 64
fi

export PATH=$HOME/.nix-profile/bin:$PATH # ci.yml installs the client via `nix profile install`

config=${GARRET_CONFIG:-.ci/garret.toml}
timeout=${GARRET_PUSH_TIMEOUT:-1800}
attempts=3

push_with_watchdog() {
  garret --config "$config" push "$@" &
  local push_pid=$!
  (
    sleep "$timeout"
    echo "garret push exceeded ${timeout}s; killing hung push" >&2
    kill -TERM "$push_pid" 2>/dev/null
  ) &
  local watchdog_pid=$!
  local status=0
  wait "$push_pid" || status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$status"
}

for attempt in $(seq 1 "$attempts"); do
  if push_with_watchdog "$@"; then
    exit 0
  fi
  if [ "$attempt" -lt "$attempts" ]; then
    echo "garret push failed (attempt $attempt/$attempts); retrying in 15s..." >&2
    sleep 15
  fi
done

echo "garret push failed after $attempts attempts" >&2
if [ "${GARRET_PUSH_STRICT:-0}" = "1" ]; then
  exit 1
fi
echo "::warning::garret push failed after $attempts attempts; continuing without cache push"
exit 0
