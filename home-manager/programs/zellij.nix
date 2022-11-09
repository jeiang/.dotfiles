{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.zellij.enable = true;

  # Temp until home-manager handles kdl for zellij
  xdg.configFile."zellij".source = ./config/zellij;
}
