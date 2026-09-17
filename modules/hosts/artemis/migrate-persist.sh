#!/usr/bin/env bash
# Copies artemis's existing state into /persist BEFORE switching to a
# persistence.* change (an added entry, or one moved between system, data,
# and cache); run ON artemis as root, from a checkout of the new revision,
# then deploy, then reboot. Switching first bind-mounts an empty /persist
# dir over any newly added entry, so running this after the switch has
# nothing left on the live path to copy.
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

# Sourced with `set -e` in effect: a failed nix eval or jq here (bad list,
# bad flake ref) must stop the script before anything is copied, not after.
dirs=$(paths directories)
files_list=$(paths files)
data_dirs=$(paths data.directories)
data_files=$(paths data.files)
cache_dirs=$(paths cache.directories)
cache_files=$(paths cache.files)

# Set by sync_dir when a directory looks like it may have lost data to an early switch;
# checked at the end so one suspect directory doesn't stop the sections after it.
warned=0

sync_dir() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    echo "skip (missing): $src"
    return
  fi
  # A non-empty bind mount is just the steady state (safe to re-sync onto itself). An
  # empty one is ambiguous: it's either a directory that never had anything (also steady
  # state, e.g. an unused Trash), or a switch already bind-mounted $dst here before this
  # script ran, in which case $src's earlier contents are gone from the live path, not
  # just unsynced. Warn either way instead of aborting the rest of the run.
  if mountpoint -q "$src" && [[ "$src" -ef "$dst" ]] && [[ -z "$(ls -A "$src" 2>/dev/null)" ]]; then
    echo "WARN: $src is an empty bind mount from $dst. If it should hold data, a switch" >&2
    echo "      likely ran before this script did -- boot the previous generation to" >&2
    echo "      recover its contents, or restore them by hand from the old rootfs under" >&2
    echo "      /old_roots, then re-run this script." >&2
    warned=1
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
    # impermanence symlinks a missing file into place instead of bind-mounting it; once the
    # app has written through that link, $src IS $dst and copying it would rsync -a the
    # symlink itself onto $dst, replacing the real file with a link to itself.
    echo "skip (already linked): $src"
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

if [[ "$warned" == 1 ]]; then
  echo
  echo "WARNING: see the WARN lines above -- one or more directories were empty" >&2
  echo "bind mounts already pointing at /persist. Confirm they should be empty" >&2
  echo "before deploying." >&2
  exit 1
fi
