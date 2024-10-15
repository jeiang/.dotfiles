{
  description = "System configuration.";

  outputs = { treefmt-nix, devenv, nixpkgs, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; }
      {
        systems = [ "x86_64-linux" "aarch64-darwin" ];
        imports = [
          treefmt-nix.flakeModule
          devenv.flakeModule
          ./devenv.nix
        ];
        flake =
          let
            modules = import ./modules;
            users = import ./users;
            home = import ./home;
          in
          {
            nixosConfigurations = {
              solder = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs modules users home; };
                modules = [
                  ./hosts/solder.nix
                ];
              };
              installer = nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                specialArgs = { inherit inputs; };
                modules = [
                  ./hosts/installer.nix
                ];
              };
            };
          };
      };

  inputs = {
    # Principal inputs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

    # Misc Packages
    helix.url = "github:helix-editor/helix";
    helix.inputs.nixpkgs.follows = "nixpkgs";

    # My Stuff
    gradle2nix.url = "github:tadfisher/gradle2nix/v2"; # website
    gradle2nix.inputs.nixpkgs.follows = "nixpkgs";
    website = {
      url = "github:jeiang/website/9aecfd696e3f4f06e9f4d802b31ebb8d7f1da48f";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.gradle2nix.follows = "gradle2nix";
    };
  };
}
