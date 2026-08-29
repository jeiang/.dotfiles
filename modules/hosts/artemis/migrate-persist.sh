#!/usr/bin/env bash
# Copies artemis's existing state into /persist before a persistence.* change;
# run ON artemis as root, and only reboot once every path reports synced.
# Usage: sudo ./migrate-persist.sh [/path/to/flake-checkout]

set -euo pipefail

flake="${1:-/etc/nixos}"
attr="nixosConfigurations.artemis.config"

# root running nix eval on a user-owned checkout trips git's "dubious ownership" check; scope safe.directory to this path only.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0="$(cd "$flake" && pwd -P)"

user=$(nix eval --impure --raw "${flake}#${attr}.preferences.user.name")
home="/home/${user}"

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

# mkdir -p as root leaves undeclared ancestor dirs root:root and impermanence mirrors that onto $HOME at boot; fix owner:group only (mode untouched, preserving the 0700 entries).
echo "== fixing ownership under /persist/{data,cache}/home/${user} =="
group="$(id -gn "$user")"
for root in "/persist/data/home/${user}" "/persist/cache/home/${user}"; do
  [[ -e "$root" ]] && chown -R "${user}:${group}" "$root"
done

echo
echo "Done. Review any 'skip (missing)' lines above — those are fine if the"
echo "path genuinely doesn't exist yet, but re-run this after any further"
echo "persistence.* changes before rebooting. nukeRoot wipes anything on /"
echo "that wasn't copied into /persist first."
