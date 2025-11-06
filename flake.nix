{
  description = "System configuration.";

  nixConfig = {
    extra-trusted-public-keys = "main:bDbTZZwnX3C+67tQxGUfZzNLNio6KTPyJrXpqjTXBWM=";
    extra-substituters = "https://attic.jeiang.dev/main";
  };

  outputs = {flake-parts, ...} @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;
      imports = [
        inputs.devenv.flakeModule
        inputs.treefmt-nix.flakeModule
        ./devenv.nix
        ./deploy.nix
        inputs.home-manager.flakeModules.home-manager
        ./modules
        ./users
        ./systems/solder
        ./systems/artemis
        ./overlays
      ];
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Utility inputs
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    # TODO: revert to serokell once https://github.com/serokell/deploy-rs/issues/340 is fixed
    deploy-rs.url = "github:jeiang/deploy-rs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    # devenv
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

    # system config
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Packages & Apps
    helix.url = "github:helix-editor/helix";
    helix.inputs.nixpkgs.follows = "nixpkgs";
    ### WARNING: DO NOT FOLLOW NIXPKGS. Gradle builds are broken for this package due to bad dependencies.
    website.url = "github:jeiang/website";
    nur.url = "github:nix-community/NUR";
    nur.inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-parts.follows = "flake-parts";
    };
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
  };
}
