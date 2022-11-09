{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.alacritty.enable = true;
  programs.alacritty.settings.shell.program = "zellij";
}
