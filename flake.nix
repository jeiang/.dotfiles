{
  description = "Nix Flake to configure my computer(s).";

  outputs = inputs @ {
    self,
    flake-parts,
    nixos-flake,
    devenv,
    treefmt-nix,
    nur,
    nix-gaming,
    agenix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        nixos-flake.flakeModule
        devenv.flakeModule
        treefmt-nix.flakeModule
      ];

      perSystem = {...}: {
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
            self.systemModules.network
            self.systemModules.nix
            self.systemModules.plymouth
            self.systemModules.security
            # TODO: move to a module
            {
              age.secrets = {
                # TODO: scan all files in secrets folder, get files with age extension and
                # expose them as their file name
                aidanp-password.file = ./secrets/aidanp-password.age;
                root-password.file = ./secrets/root-password.age;
              };
              age.identityPaths = [
                "/persist/etc/ssh/ssh_host_ed25519_key"
                "/persist/etc/ssh/ssh_host_rsa_key"
                # TODO: expose these keys somewhere?
                # "/persist/home/aidanp/.ssh/id_ed25519"
                # "/persist/home/aidanp/.ssh/id_rsa"
              ];
            }

            # Users
            # TODO: add a root user dir
            ({config, ...}: {
              users.users.root = {
                hashedPasswordFile = config.age.secrets.root-password.path;
              };
            })
            ./users/aidanp

            # Modules
            self.nixosModules.home-manager
            nur.nixosModules.nur
            {nixpkgs.overlays = [nur.overlay];}
            nix-gaming.nixosModules.pipewireLowLatency
            agenix.nixosModules.default

            # Misc Config
            {
              home-manager.extraSpecialArgs = {
                inherit inputs;
              };
            }
          ];
        };

        homeModules = import ./modules/home {};
        systemModules = import ./modules/system {};
      };
    };

  inputs = {
    # Principle inputs (updated by `nix run .#update`)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/nur";

    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-flake.url = "github:srid/nixos-flake";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
    hyprcontrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprportal = {
      url = "github:hyprwm/xdg-desktop-portal-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  nixConfig = {
    allowUnfree = true;
    extra-experimental-features = "nix-command flakes";
    extra-substituters = [
      "https://nrdxp.cachix.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://jeiang.cachix.org"
      "https://nix-gaming.cachix.org"
      "https://helix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
    ];
  };
}
