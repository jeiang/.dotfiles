{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.nix-darwin.flakeModules.default];

  options = {
    flake = inputs.flake-parts.lib.mkSubmoduleOptions {
      diskoConfigurations = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = {};
      };
      deploy = lib.mkOption {
        type = lib.types.submodule {
          options.nodes = lib.mkOption {
            type = lib.types.attrsOf lib.types.raw;
          };
        };
        default = {};
      };
      # flake-parts core declares neither flake.lib nor a merge for it; without this, a second module setting flake.lib.<key> hits flake-parts' freeform "defined multiple times" error.
      lib = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = {};
      };
    };
  };

  config = {
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];

    perSystem = {
      config,
      pkgs,
      ...
    }: {
      # Packages for one platform only: absent on the other rather than an eval error there.
      options = {
        linuxPackages = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.package;
          default = {};
        };
        darwinPackages = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.package;
          default = {};
        };
      };
      config.packages = lib.mkMerge [
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux config.linuxPackages)
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin config.darwinPackages)
      ];
    };
  };
}
