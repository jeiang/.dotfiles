{
  inputs,
  lib,
  ...
}: {
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
    };
  };

  config = {
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
  };
}
