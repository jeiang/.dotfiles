# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)

{ inputs, outputs, lib, config, pkgs, ... }: {
  imports = [
    ./dconf.nix
    ./environment.nix
    ./impermanence.nix
    ./services
    ./programs
  ];

  # Information about the current user
  home = {
    username = "aidanp";
    homeDirectory = "/home/aidanp";
  };

  # Enable fonts to be installed as packages
  fonts.fontconfig.enable = true;

  # Enable home-manager and git
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "22.05";
}
