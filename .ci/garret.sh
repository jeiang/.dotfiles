#!/usr/bin/env bash
# Pushes to garret as CI builds: nix's post-build hook wakes a background
# `garret watch-store`, and a last step stops it and drains what is left.
set -euo pipefail

tmp=$RUNNER_TEMP
client=$tmp/garret/bin/garret
config=$tmp/garret.toml
socket=$tmp/garret.sock
cursor=$tmp/garret-cursor
log=$tmp/garret-watch.log
pidfile=$tmp/garret-watch.pid
# The job's build step writes its out paths here.
outputs=$tmp/garret-outputs

case ${1:-} in
hook)
  # Every build runs it, so it must exit 0, also while the client is absent.
  cat >"$tmp/garret-hook" <<EOF
#!/bin/sh
[ -x "$client" ] || exit 0
exec "$client" enqueue --socket "$socket"
EOF
  chmod +x "$tmp/garret-hook"
  ;;
watch)
  rev=$(jq -r '.nodes.garret.locked.rev' flake.lock)
  nix build --out-link "$tmp/garret" "github:jeiang/garret/${rev}#garret"
  # Paths substituted from garret itself are skipped one by one; the drain's
  # push of the job's outputs still marks their closures as pushed now.
  {
    cat .ci/garret.toml
    printf '\n[watch]\ncursor_path = "%s"\nsocket_path = "%s"\nupstream_keys = ["cache.nixos.org-1", "%s"]\n' \
      "$cursor" "$socket" "${GARRET_PUBLIC_KEY%%:*}"
  } >"$config"
  nohup "$client" --config "$config" watch-store >"$log" 2>&1 &
  echo $! >"$pidfile"
  # The cursor appears once the watcher has authenticated and bootstrapped.
  for _ in $(seq 30); do
    [ -s "$cursor" ] && exit 0
    sleep 1
  done
  cat "$log" >&2
  exit 1
  ;;
drain)
  if [ -s "$pidfile" ]; then
    pid=$(cat "$pidfile")
    kill "$pid" 2>/dev/null || true
    # The drain takes over the watcher's cursor.
    for _ in $(seq 30); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    tail -n 100 "$log"
  fi
  status=0
  "$client" --config "$config" watch-store --drain || status=$?
  if [ -s "$outputs" ]; then
    # shellcheck disable=SC2046 # one store path per line
    "$client" --config "$config" push $(cat "$outputs") || status=$?
  fi
  exit "$status"
  ;;
*)
  echo "usage: $0 hook|watch|drain" >&2
  exit 64
  ;;
esac
