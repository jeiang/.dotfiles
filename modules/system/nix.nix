{
  lib,
  inputs,
  ...
}: {
  nix = let
    # pin the registry to avoid downloading and evaling a new nixpkgs version every time
    registry = lib.mapAttrs (_: v: {flake = v;}) inputs;
  in {
    inherit registry;
    # auto garbage collect
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    optimise = {
      automatic = true;
      dates = ["03:45"];
    };

    # set the path for channels compat
    nixPath = lib.mapAttrsToList (key: _: "${key}=flake:${key}") registry;

    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      flake-registry = "/etc/nix/registry.json";

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      substituters = [
        "https://helix.cachix.org"
        "https://hyprland.cachix.org"
        "https://jeiang.cachix.org"
        "https://nix-community.cachix.org"
        "https://walker.cachix.org"
      ];
      trusted-public-keys = [
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (_: _: {
        # Expose inputs for overlays
        inputs' = inputs;
      })
      inputs.helix.overlays.default
      inputs.nur.overlays.default
    ];
  };
}
