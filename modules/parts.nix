{
  inputs,
  lib,
  moduleLocation,
  ...
}: {
  # nix-darwin's own flake-parts module gives `flake.darwinConfigurations`
  # the same treatment flake-parts core gives `flake.nixosConfigurations`
  # (a proper lazyAttrsOf-raw option, not a freeform passthrough).
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
      # Neither flake-parts core nor nix-darwin declares `darwinModules`, so
      # without this, every module beyond the first one that sets
      # `flake.darwinModules.<name>` would hit flake-parts' freeform
      # "defined multiple times while it's expected to be unique" error
      # (verified by trial). Mirrors flake-parts' own
      # `modules/nixosModules.nix` (lazyAttrsOf deferredModule, `_class` set
      # for module-system type-checking) so darwin modules get the exact
      # same multi-file registration support `flake.nixosModules` already
      # has.
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
