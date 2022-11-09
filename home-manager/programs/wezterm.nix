{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.wezterm.enable = true;
  programs.wezterm.extraConfig = builtins.readFile ./config/wezterm/wezterm.lua;
}
