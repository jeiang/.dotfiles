#!/usr/bin/env bash
# Copies artemis's existing state into /persist before a persistence.* change.
# Run on artemis as root from a checkout of the new revision, then deploy, then reboot.
# Usage: sudo ./migrate-persist.sh [/path/to/flake-checkout]

set -euo pipefail

flake=$(cd "${1:-/etc/nixos}" && pwd -P)
attr="nixosConfigurations.artemis.config"

# Nix refuses a git checkout owned by another user, so evaluate as the checkout's owner.
owner=$(stat -c %U "$flake")
nix_eval() {
  runuser -u "$owner" -- nix eval --impure "$@"
}

user=$(nix_eval --raw "${flake}#${attr}.preferences.user.name")
home="/home/${user}"

paths() {
  nix_eval --json "${flake}#${attr}.persistence.$1" \
    --apply 'builtins.map (e: if builtins.isString e then e else e.directory or e.file)' |
    jq -r '.[]'
}

# Load every list first so a failed eval stops the script before anything is copied.
dirs=$(paths directories)
files_list=$(paths files)
data_dirs=$(paths data.directories)
data_files=$(paths data.files)
cache_dirs=$(paths cache.directories)
cache_files=$(paths cache.files)

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

sync_list() {
  local list="$1" fn="$2" src_prefix="$3" dst_prefix="$4"
  [[ -z "$list" ]] && return 0
  while IFS= read -r p; do
    "$fn" "${src_prefix}${p}" "${dst_prefix}${p}"
  done <<<"$list"
}

echo "== system directories -> /persist =="
sync_list "$dirs" sync_dir "" "/persist"

echo "== system files -> /persist =="
sync_list "$files_list" sync_file "" "/persist"

echo "== user data directories -> /persist/data/home/${user} =="
sync_list "$data_dirs" sync_dir "${home}/" "/persist/data/home/${user}/"

echo "== user data files -> /persist/data/home/${user} =="
sync_list "$data_files" sync_file "${home}/" "/persist/data/home/${user}/"

echo "== user cache directories -> /persist/cache/home/${user} =="
sync_list "$cache_dirs" sync_dir "${home}/" "/persist/cache/home/${user}/"

echo "== user cache files -> /persist/cache/home/${user} =="
sync_list "$cache_files" sync_file "${home}/" "/persist/cache/home/${user}/"

# mkdir -p as root leaves undeclared ancestor dirs root:root and impermanence mirrors that onto $HOME at boot; fix owner:group only (mode untouched, preserving the 0700 entries).
echo "== fixing ownership under /persist/{data,cache}/home/${user} =="
group="$(id -gn "$user")"
for root in "/persist/data/home/${user}" "/persist/cache/home/${user}"; do
  [[ -e "$root" ]] && chown -R "${user}:${group}" "$root"
done

echo
echo "Done. Review any 'skip (missing)' lines above — those are fine if the"
echo "path genuinely doesn't exist yet. Re-run this before switching to any"
echo "further persistence.* change: nukeRoot wipes anything on / that wasn't"
echo "copied into /persist first."
