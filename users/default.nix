{
  flake-parts-lib,
  self,
  inputs,
  ...
}: let
  inherit (flake-parts-lib) importApply;
in {
  flake.nixosModules = {
    user-aidanp = importApply ./aidanp.nix {
      localFlake = self;
      inherit inputs;
    };
    user-root = import ./root.nix;
  };
}
