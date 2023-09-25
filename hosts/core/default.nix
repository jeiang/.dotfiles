{
  pkgs,
  lib,
  inputs,
  config,
  ...
}:
# configuration shared by all hosts
{
  # pickup pkgs from flake export
  nixpkgs.pkgs = inputs.self.legacyPackages.${config.nixpkgs.system};

  documentation.dev.enable = true;

  time.timeZone = lib.mkDefault "America/Port_of_Spain";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    # saves space
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "ja_JP.UTF-8/UTF-8"
    ];
  };

  # graphics drivers / HW accel
  hardware.opengl.enable = true;

  # enable programs
  programs = {
    less.enable = true;
    fish.enable = true;
    nix-ld.enable = true;
  };

  # Env Stuff
  environment.shells = with pkgs; [zsh fish];

  # compresses half the ram for use as swap
  zramSwap.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = lib.mkDefault "23.11"; # Did you read the comment?
}
