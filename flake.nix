{
  description = "Nix Flake to configure my computer(s).";

  outputs =
    inputs @ { self
    , agenix
    , devenv
    , flake-parts
    , impermanence
    , helix
    , nix-gaming
    , nixos-flake
    , nixpkgs
    , nur
    , nvfetcher
    , treefmt-nix
    , ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [
        nixos-flake.flakeModule
        devenv.flakeModule
        treefmt-nix.flakeModule
      ];

      perSystem = { system, ... }: {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [
            agenix.overlays.default
            nvfetcher.overlays.default
            helix.overlays.default
          ];
        };
        imports = [
          ./devenv
        ];
      };

      flake = {
        # Configurations for Linux (NixOS) machines
        nixosConfigurations.ark = self.nixos-flake.lib.mkLinuxSystem {
          nixpkgs.hostPlatform = "x86_64-linux";
          _module.args = {
            inherit inputs;
            inherit (self) homeModules;
          };
          imports = [
            # Basic config
            ./hosts/core
            ./hosts/ark
            self.systemModules.bluetooth
            self.systemModules.desktop
            self.systemModules.doas
            self.systemModules.gamemode
            self.systemModules.greetd
            self.systemModules.impermanence
            self.systemModules.network
            self.systemModules.nix
            self.systemModules.plymouth
            self.systemModules.security
            self.systemModules.steam
            ./secrets

            # Users
            ./users/aidanp
            ./users/root.nix

            # Modules
            agenix.nixosModules.default
            impermanence.nixosModules.impermanence
            nix-gaming.nixosModules.pipewireLowLatency
            nix-gaming.nixosModules.steamCompat
            nur.nixosModules.nur
            self.nixosModules.home-manager

            # Misc Config
            {
              home-manager.extraSpecialArgs = {
                inherit inputs;
              };
            }
          ];
        };

        homeModules = import ./modules/home { };
        systemModules = import ./modules/system { };
      };
    };

  inputs = {
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprcontrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprpaper = {
      url = "github:hyprwm/hyprpaper";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprportal = {
      url = "github:hyprwm/xdg-desktop-portal-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    nixos-flake.url = "github:srid/nixos-flake";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/nur";
    nvfetcher = {
      url = "github:berberman/nvfetcher";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    allowUnfree = true;
    extra-experimental-features = "nix-command flakes";
    extra-substituters = [
      "https://cache.privatevoid.net"
      "https://helix.cachix.org"
      "https://hyprland.cachix.org"
      "https://jeiang.cachix.org"
      "https://nix-community.cachix.org"
      "https://nix-gaming.cachix.org"
      "https://nrdxp.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.privatevoid.net:SErQ8bvNWANeAvtsOESUwVYr2VJynfuc9JRwlzTTkVg="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4="
    ];
  };
}
