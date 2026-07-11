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

# `nix eval --impure` shells out to git for a local git+file:// flake input.
# This script runs as root, but the checkout is normally owned by a regular
# user, so git's ownership check ("detected dubious ownership in
# repository") blocks it unless the path is explicitly marked safe for this
# process. Scope that to just this flake path rather than disabling the
# check globally for root.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0="$(cd "$flake" && pwd -P)"

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
  local dst_parent
  dst_parent="$(dirname "$dst")"
  mkdir -p "$dst_parent"
  # No trailing slash on $src: every call site here builds $dst as some
  # prefix + $src's own path, so basename "$src" always equals basename
  # "$dst". That lets rsync copy the directory itself (with its own
  # owner/mode/xattrs, not just its contents) into $dst_parent — otherwise
  # $dst would come back root:root 0755 regardless of what the source
  # directory's permissions were (e.g. .ssh, .gnupg, system-connections).
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

# The `mkdir -p` calls in sync_dir/sync_file run as root and only create
# ancestor directories that aren't themselves a declared persistence entry
# (e.g. .config, .local, .local/share, .local/state, .cache — none of
# which are individually listed, only paths nested inside them). Left
# alone those come back root:root, and impermanence mirrors that ownership
# onto the live $HOME tree at boot instead of creating it fresh as the
# user, breaking every app that expects to write into its own XDG dirs.
# Force correct ownership on the whole user tree; this only touches
# owner:group, never mode, so it doesn't disturb the explicit 0700 entries
# (.ssh, .gnupg, etc.) synced above.
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
