{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      {
        systems = [ "x86_64-linux" "aarch64-darwin" ];
        imports = [
          inputs.treefmt-nix.flakeModule
          inputs.devenv.flakeModule
          ./devenv.nix
        ];
        perSystem = _: { };
        flake =
          let
            lib = import ./lib.nix { inherit inputs; };
          in
          {
            nixosConfigurations = {
              ark = lib.mkNixos ./hosts/ark;
              # solder = lib.mkNixos ./hosts/solder;
            };
            darwinConfigurations = {
              zakkart = lib.mkDarwin ./hosts/zakkart;
            };

            nixosModules = { };
            darwinModules = { };
          };
      };

  inputs = {
    # Principal inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Utility inputs
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Dev Shell
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # Encrypted secrets
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Disks and partitions
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
}
