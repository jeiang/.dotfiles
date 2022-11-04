{ inputs, lib, config, pkgs, ... }: {
  # Wezterm file config
  programs.wezterm.extraConfig = builtins.readFile ./config/wezterm/wezterm.lua;

  # Zellij kdl file config
  xdg.configFile."zellij".source = ./config/zellij;
}
