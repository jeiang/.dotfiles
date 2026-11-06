#!/usr/bin/env bash
# Lists paths in artemis's /persist that no persistence.* entry declares.
# Read-only: it evaluates this checkout and lists directories over SSH.
# Usage: ./persist-orphans.sh [flake] [host]

set -euo pipefail

flake=${1:-.}
config="${flake}#nixosConfigurations.artemis.config"
host=${2:-$(nix eval --raw "${flake}#deploy.nodes.artemis.hostname")}
snapshot=$(nix eval --raw "${config}.backups.persist.snapshot")

declared=$(nix eval --json "${config}.persistence.entries" | jq -r '.[].stored' | sort -u)

# Every strict ancestor of a declared path, down to /persist itself.
ancestors=$(while read -r path; do
  while [[ $path != /persist ]]; do
    path=${path%/*}
    echo "$path"
  done
done <<<"$declared" | sort -u)

# Children of each ancestor; the backup job's transient snapshot is not state.
# shellcheck disable=SC2086 # declared paths contain no whitespace
children=$(ssh "$host" find $ancestors -mindepth 1 -maxdepth 1 |
  grep -vx "$snapshot" | sort -u)

comm -23 <(echo "$children") <(sort -u <(echo "$declared") <(echo "$ancestors"))
