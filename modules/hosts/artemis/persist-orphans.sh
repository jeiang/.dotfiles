#!/usr/bin/env bash
# Lists paths in artemis's /persist that no persistence.* entry declares.
# Read-only: it evaluates this checkout and lists directories over SSH.
# Usage: ./persist-orphans.sh [flake] [host]

set -euo pipefail

flake=${1:-.}
host=${2:-artemis.jeiang.vpn}

declared=$(nix eval --json "${flake}#nixosConfigurations.artemis.config.environment.persistence" --apply '
  persistence: builtins.concatLists (builtins.attrValues (builtins.mapAttrs (root: p:
    let
      entries = p.directories ++ p.files ++ builtins.concatLists (builtins.map (u: u.directories ++ u.files) (builtins.attrValues p.users));
    in builtins.map (e: root + (e.dirPath or e.filePath)) entries) persistence))' | jq -r '.[]' | sort -u)

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
  grep -vx /persist/.backup-snapshot | sort -u)

comm -23 <(echo "$children") <(sort -u <(echo "$declared") <(echo "$ancestors"))
