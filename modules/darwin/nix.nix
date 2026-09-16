{
  inputs,
  withSystem,
  ...
}: {
  # Determinate Nix forces nix.enable = false, so every nix.settings equivalent must go through determinateNix.customSettings.
  flake.darwinModules.nix = {config, ...}: {
    imports = [inputs.determinate.darwinModules.default];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    determinateNix = {
      registry.nixpkgs.flake = inputs.nixpkgs;

      customSettings = {
        connect-timeout = 5;
        fallback = true;

        keep-derivations = true;
        keep-outputs = true;

        # extra-, not the bare keys: customSettings does no NixOS-style merging, so bare substituters/trusted-public-keys would replace Determinate's defaults and drop cache.nixos.org.
        extra-substituters = [
          "https://cache.jeiang.dev"
        ];
        extra-trusted-public-keys = [
          "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA="
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
