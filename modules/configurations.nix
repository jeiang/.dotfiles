{
  inputs,
  lib,
  config,
  ...
}: {
  options = {
    nixos.modules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
    };
    nixos.configurations = lib.mkOption {
      type = lib.types.lazyAttrsOf (lib.types.submodule {
        options.module = lib.mkOption {
          type = lib.types.deferredModule;
        };
      });
      default = {};
    };

    darwin.modules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
    };
    darwin.configurations = lib.mkOption {
      type = lib.types.lazyAttrsOf (lib.types.submodule {
        options.module = lib.mkOption {
          type = lib.types.deferredModule;
        };
      });
      default = {};
    };
  };

  config = {
    flake.nixosConfigurations =
      lib.mapAttrs (
        _: cfg:
          inputs.nixpkgs.lib.nixosSystem {
            modules = [cfg.module];
          }
      )
      config.nixos.configurations;

    flake.darwinConfigurations =
      lib.mapAttrs (
        _: cfg:
          inputs.nix-darwin.lib.darwinSystem {
            modules = [cfg.module];
          }
      )
      config.darwin.configurations;
  };
}
