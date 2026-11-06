{
  inputs,
  lib,
  config,
  ...
}: let
  modulesOption = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = {};
  };
  configurationsOption = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule {
      options.module = lib.mkOption {
        type = lib.types.deferredModule;
      };
    });
    default = {};
  };
in {
  options = {
    nixos.modules = modulesOption;
    nixos.configurations = configurationsOption;
    darwin.modules = modulesOption;
    darwin.configurations = configurationsOption;
    # Class-agnostic roles: `base` is every host, `workstation` is artemis and every darwin host.
    shared.modules = modulesOption;
  };

  config = {
    nixos.modules = {
      base.imports = [config.shared.modules.base];
      artemis.imports = [config.shared.modules.workstation];
    };
    darwin.modules.base.imports = [
      config.shared.modules.base
      config.shared.modules.workstation
    ];

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
