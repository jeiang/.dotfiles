{
  inputs,
  withSystem,
  ...
}: {
  # Determinate Nix (docs/adr/0008) forces nix.enable = false, so every nix.settings equivalent must go through determinateNix.customSettings.
  flake.darwinModules.nix = {config, ...}: {
    imports = [inputs.determinate.darwinModules.default];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    determinateNix = {
      registry = builtins.mapAttrs (_: v: {flake = v;}) inputs;

      customSettings = {
        connect-timeout = 5;
        fallback = true;

        keep-derivations = true;
        keep-outputs = true;

        # extra-, not the bare keys: customSettings does no NixOS-style merging, so bare substituters/trusted-public-keys would replace Determinate's defaults and drop cache.nixos.org.
        extra-substituters = [
          "https://cache.jeiang.dev"
          "https://helix.cachix.org"
        ];
        extra-trusted-public-keys = [
          "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA="
          "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        ];
        # @admin, not @wheel: macOS's wheel group has no members besides root.
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
