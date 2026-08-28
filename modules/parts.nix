{
  inputs,
  lib,
  moduleLocation,
  ...
}: {
  imports = [inputs.nix-darwin.flakeModules.default];

  options = {
    flake = inputs.flake-parts.lib.mkSubmoduleOptions {
      diskoConfigurations = inputs.nixpkgs.lib.mkOption {
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
      # Neither flake-parts core nor nix-darwin declares darwinModules, and flake.lib has no declared option either; without these, a second module setting either hits flake-parts' freeform "defined multiple times" error.
      lib = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = {};
      };
      darwinModules = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.deferredModule;
        default = {};
        apply = lib.mapAttrs (k: v: {
          _class = "darwin";
          _file = "${toString moduleLocation}#darwinModules.${k}";
          imports = [v];
        });
      };
    };
  };

  config = {
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
  };
}
