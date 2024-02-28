{ config
, pkgs
, lib
, inputs
, ...
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
    registry = lib.mapAttrs (_: v: { flake = v; }) inputs;

    # set the path for channels compat
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") config.nix.registry;

    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [ "nix-command" "flakes" ];
      flake-registry = "/etc/nix/registry.json";

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      substituters = [
        "https://helix.cachix.org"
        "https://hyprland.cachix.org"
        "https://jeiang.cachix.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      trusted-users = [ "root" "@wheel" ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      inputs.agenix.overlays.default
      inputs.helix.overlays.default
      inputs.hyprcontrib.overlays.default
      inputs.hyprland.overlays.default
      inputs.nur.overlay
      inputs.nvfetcher.overlays.default

      # Expose inputs for overlays
      (_: _: {
        inputs' = inputs;
      })

      (import ./pkgs)
      (import ./overlays/devenv.nix)
      (import ./overlays/nix-gaming.nix)
      (import ./overlays/nwjs.nix)
      (import ./overlays/steam.nix)
      (import ./overlays/wezterm.nix)
    ];
  };
}
