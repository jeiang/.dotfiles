{ inputs, ... }:
let

  specialArgs = rec {
    nixos = {
      flake = {
        inherit inputs;
        inherit (inputs) self;
      };
    };
    darwin = nixos // {
      rosettaPkgs = import inputs.nixpkgs { system = "x86_64-darwin"; };
    };
  };
in
{
  mkNixos = mod: inputs.nixpkgs.lib.nixosSystem {
    specialArgs = specialArgs.nixos;
    modules = [
      # Actual System Config
      mod

      # Home manager
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = specialArgs.nixos;
        };
      }
    ];
  };
  mkDarwin = mod: inputs.nix-darwin.lib.darwinSystem {
    specialArgs = specialArgs.darwin;
    modules = [
      # Actual system config
      mod

      # Home Manager
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = specialArgs.darwin;
        };
      }
    ];
  };
}
