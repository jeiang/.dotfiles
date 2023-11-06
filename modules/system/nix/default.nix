{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  environment.systemPackages = [
    # we need git for flakes
    pkgs.git
  ];

  nix = {
    # auto garbage collect
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    # pin the registry to avoid downloading and evaling a new nixpkgs version every time
    registry = lib.mapAttrs (_: v: {flake = v;}) inputs;

    # set the path for channels compat
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;

    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = ["nix-command" "flakes"];
      flake-registry = "/etc/nix/registry.json";

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      substituters = [
        "https://nrdxp.cachix.org"
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
        "https://jeiang.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://helix.cachix.org"
        "https://cache.privatevoid.net"
      ];
      trusted-public-keys = [
        "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        "cache.privatevoid.net:SErQ8bvNWANeAvtsOESUwVYr2VJynfuc9JRwlzTTkVg="
      ];
      trusted-users = ["root" "@wheel"];
    };
  };

  # TODO: put in own folder, use nvfetcher like before
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      inputs.nur.overlay
      inputs.agenix.overlays.default
      inputs.nvfetcher.overlays.default
      (import ./pkgs)
      (import ./overlays/wezterm.nix)
      (
        _: prev: {
          steam = prev.steam.override {
            extraPkgs = pkgs:
              with pkgs; [
                keyutils
                libkrb5
                libpng
                libpulseaudio
                libvorbis
                stdenv.cc.cc.lib
                xorg.libXcursor
                xorg.libXi
                xorg.libXinerama
                xorg.libXScrnSaver
              ];
            extraProfile = "export GDK_SCALE=2";
          };
        }
      )
    ];
  };
}
