#!/usr/bin/env nix-shell
#!nix-shell -i bash -p lua
# make this pure lua

workspaces() {
  lua ./scripts/workspaces.lua
}
workspaces
tail -f /tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log | grep --line-buffered "Changed to workspace" | while read -r; do
  workspaces
done
