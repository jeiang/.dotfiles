# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, lib, config, pkgs, ... }: {
  imports = [
    ./programs.nix
    ./packages.nix
    ./services.nix
    ./persist.nix
    ./dconf.nix
  ];

  # Information about the current user
  home = {
    username = "aidanp";
    homeDirectory = "/home/aidanp";
  };

  # Environment Variables
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    EDITOR = "hx";
  };

  # Enable fonts to be installed as packages
  fonts.fontconfig.enable = true;

  # Manual configuration for other programs not handled by Home Manager
  xdg.configFile = { };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "22.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
