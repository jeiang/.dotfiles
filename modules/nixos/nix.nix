{
  inputs,
  withSystem,
  ...
}: {
  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  };

  nixos.modules.nix = {config, ...}: {
    imports = [
      # Determinate keeps the stock nix.* options and renders them to /etc/nix/nix.custom.conf.
      inputs.determinate.nixosModules.default
    ];

    nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({pkgs, ...}: pkgs);

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 14";
    };

    nix = {
      registry.nixpkgs.flake = inputs.nixpkgs;
      # set the path for channels compat
      nixPath = ["nixpkgs=flake:nixpkgs"];

      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        flake-registry = "/etc/nix/registry.json";

        # Self-hosted cache; do not let an outage stall deploys
        connect-timeout = 5;
        fallback = true;

        substituters = [
          "https://cache.jeiang.dev"
        ];
        trusted-public-keys = [
          "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA="
        ];
        trusted-users = ["root"];
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
