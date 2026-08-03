{
  inputs,
  withSystem,
  ...
}: {
  # Determinate Nix owns the Nix installation on zakkart (docs/adr/0008):
  # its module forces `nix.enable = false` itself (determinateNix.enable
  # defaults to true), so nix-darwin's own `nix.*` options never apply
  # here. Everything modules/nixos/nix.nix expresses through `nix.settings`
  # has to go through `determinateNix.customSettings` instead, which the
  # imported module renders to /etc/nix/nix.custom.conf.
  flake.darwinModules.nix = {config, ...}: {
    imports = [inputs.determinate.darwinModules.default];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    determinateNix = {
      # Same registry pinning as modules/nixos/nix.nix, to avoid evaling a
      # fresh nixpkgs for every flake-relative CLI lookup.
      registry = builtins.mapAttrs (_: v: {flake = v;}) inputs;

      customSettings = {
        # attic.jeiang.dev is self-hosted; don't let a cache outage stall
        # builds (matches modules/nixos/nix.nix).
        connect-timeout = 5;
        fallback = true;

        keep-derivations = true;
        keep-outputs = true;

        # extra- (append), not the bare keys: `customSettings` renders
        # straight into /etc/nix/nix.custom.conf with no NixOS-style
        # default-merging, so a plain `substituters`/`trusted-public-keys`
        # here would *replace* Determinate's own default list -- silently
        # dropping cache.nixos.org and forcing the reset machine to build
        # nixpkgs from source instead of substituting it. No hyprland
        # cachix here (Linux-only, artemis/legion only).
        extra-substituters = [
          "https://attic.jeiang.dev/default"
          "https://helix.cachix.org"
        ];
        extra-trusted-public-keys = [
          "default:Xaqeg5b1ctNwH4sEWG+nt1kSpGPpFG0zivJUbZyCfdM="
          "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        ];
        # extra- here too, same reasoning as the substituters above --
        # trusted-users is one of customSettings' explicit options, so a
        # bare assignment would still replace Determinate's own default
        # rather than merge with it. `@wheel` is also wrong on macOS: it's
        # the NixOS admin-user convention, but macOS's wheel group has no
        # members besides root -- the macOS equivalent is `@admin`.
        extra-trusted-users = ["@admin"];
      };
    };

    hjem.users.${config.preferences.user.name}.files.".config/nixpkgs/config.nix".text =
      # nix
      ''
        {
          allowUnfree = true;
        }
      '';
  };
}
