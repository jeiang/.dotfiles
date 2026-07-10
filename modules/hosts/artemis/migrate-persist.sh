#!/usr/bin/env bash
# Copy artemis's existing state into /persist before switching to (or
# extending) a configuration with persistence.enable/persistence.nukeRoot.enable.
#
# impermanence never migrates data on its own (see
# modules/nixos/impermanence.nix): once persistence.nukeRoot.enable is
# active, anything at a listed path that hasn't been copied into /persist
# beforehand is gone on the next boot, since the whole "/rootfs" subvolume
# gets rolled back to empty in the initrd.
#
# Run this ON artemis itself, as root, against the flake checkout that has
# the persistence entries you're about to deploy, and only reboot once it
# reports every path synced (or intentionally skipped).
#
# Usage: sudo ./migrate-persist.sh [/path/to/flake-checkout]

set -euo pipefail

flake="${1:-/etc/nixos}"
attr="nixosConfigurations.artemis.config"

user=$(nix eval --impure --raw "${flake}#${attr}.preferences.user.name")
home="/home/${user}"

# Coerce impermanence's mixed string / { directory|file = ...; mode = ...; }
# entries down to plain path strings.
paths() {
  nix eval --impure --json "${flake}#${attr}.persistence.$1" \
    --apply 'builtins.map (e: if builtins.isString e then e else e.directory or e.file)' |
    jq -r '.[]'
}

sync_dir() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "skip (missing): $src"
    return
  fi
  mkdir -p "$dst"
  rsync -aHAX --numeric-ids "$src/" "$dst/"
  echo "synced dir:  $src -> $dst"
}

sync_file() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "skip (missing): $src"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  rsync -aHAX --numeric-ids "$src" "$dst"
  echo "synced file: $src -> $dst"
}

echo "== system directories -> /persist =="
while IFS= read -r p; do
  sync_dir "$p" "/persist${p}"
done < <(paths directories)

echo "== system files -> /persist =="
while IFS= read -r p; do
  sync_file "$p" "/persist${p}"
done < <(paths files)

echo "== user data directories -> /persist/data/home/${user} =="
while IFS= read -r p; do
  sync_dir "${home}/${p}" "/persist/data/home/${user}/${p}"
done < <(paths data.directories)

echo "== user data files -> /persist/data/home/${user} =="
while IFS= read -r p; do
  sync_file "${home}/${p}" "/persist/data/home/${user}/${p}"
done < <(paths data.files)

echo "== user cache directories -> /persist/cache/home/${user} =="
while IFS= read -r p; do
  sync_dir "${home}/${p}" "/persist/cache/home/${user}/${p}"
done < <(paths cache.directories)

echo "== user cache files -> /persist/cache/home/${user} =="
while IFS= read -r p; do
  sync_file "${home}/${p}" "/persist/cache/home/${user}/${p}"
done < <(paths cache.files)

echo
echo "Done. Review any 'skip (missing)' lines above — those are fine if the"
echo "path genuinely doesn't exist yet, but re-run this after any further"
echo "persistence.* changes before rebooting. nukeRoot wipes anything on /"
echo "that wasn't copied into /persist first."
