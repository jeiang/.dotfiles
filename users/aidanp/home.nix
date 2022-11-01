# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors), use something like:
    # inputs.nix-colors.homeManagerModule
    ./programs.nix
    ./packages.nix
    ./services.nix
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

  # Configuration through dconf
  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "wezterm";
      exec-args = "start --";
    };
  };

  # Manual configuration for other programs not handled by Home Manager
  xdg.configFile = {
    "wezterm".source = ./config/wezterm;
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "22.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
