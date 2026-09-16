#!/usr/bin/env bash
# Push store paths to garret with retries and a per-attempt watchdog; a cache outage warns but never fails CI.
# GARRET_PUSH_STRICT=1 makes exhausted retries fail; GARRET_PUSH_TIMEOUT sets the watchdog in seconds.
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
