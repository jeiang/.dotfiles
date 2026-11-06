#!/usr/bin/env bash
# Copies artemis's existing state into /persist before a persistence.* change.
# Run on artemis as root from a checkout of the new revision, then deploy, then reboot.
# Usage: sudo ./migrate-persist.sh /path/to/flake-checkout

set -euo pipefail

flake=$(cd "$1" && pwd -P)

# Nix refuses a git checkout owned by another user, so evaluate as the checkout's owner.
owner=$(stat -c %U "$flake")

# Load every entry first so a failed eval stops the script before anything is copied.
entries=$(runuser -u "$owner" -- nix eval --json "${flake}#nixosConfigurations.artemis.config.persistence.entries")

sync_dir() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "skip (missing): $src"
    return
  fi
  if [[ "$src" -ef "$dst" ]]; then
    echo "skip (already persisted): $src"
    return
  fi
  local dst_parent
  dst_parent="$(dirname "$dst")"
  mkdir -p "$dst_parent"
  # No trailing slash on $src: rsync must copy the directory itself so its own owner/mode/xattrs land in $dst_parent, not root:root 0755.
  rsync -aHAX --numeric-ids "$src" "$dst_parent/"
  echo "synced dir:  $src -> $dst"
}

sync_file() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "skip (missing): $src"
    return
  fi
  if [[ "$src" -ef "$dst" ]]; then
    echo "skip (already persisted): $src"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  rsync -aHAX --numeric-ids "$src" "$dst"
  echo "synced file: $src -> $dst"
}

echo "== persisted paths -> /persist =="
while IFS=$'\t' read -r kind live stored; do
  if [[ "$kind" == dir ]]; then
    sync_dir "$live" "$stored"
  else
    sync_file "$live" "$stored"
  fi
done < <(jq -r '.[] | [.kind, .live, .stored] | @tsv' <<<"$entries")

# mkdir -p as root leaves undeclared ancestor dirs root:root and impermanence mirrors that onto $HOME at boot; fix owner:group only (mode untouched, preserving the 0700 entries).
echo "== fixing ownership of persisted homes =="
while IFS=$'\t' read -r user home; do
  if [[ -e "$home" ]]; then
    chown -R "${user}:$(id -gn "$user")" "$home"
  fi
done < <(jq -r '.[] | select(.user) | [.user, .storedHome] | @tsv' <<<"$entries" | sort -u)
