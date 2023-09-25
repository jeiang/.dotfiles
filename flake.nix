{
  description = "Nix Flake to configure my computer(s).";

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    nixos-flake,
    devenv,
    treefmt-nix,
    nixos-generators,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        nixos-flake.flakeModule
        devenv.flakeModule
        treefmt-nix.flakeModule
      ];
      systems = ["x86_64-linux"];
      perSystem = {pkgs, ...}: {
        imports = [
          ./devenv
        ];

        packages = {
          bootstrap-iso = nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "install-iso";
            specialArgs = {inherit inputs pkgs;};
            modules = [
              ./hosts/core
              ./hosts/bootstrap-iso.nix

              ./modules/network.nix
              ./modules/nix.nix

              ({_}: {
                # if needed, expose inputs to home manager
                home-manager.extraSpecialArgs = {inherit inputs;};
              })

              # Setup home-manager in NixOS config
              self.nixosModules.home-manager
            ];
          };
        };
      };
      flake = let
        mainUser = "aidanp";
      in {
        # Configurations for Linux (NixOS) machines
        nixosConfigurations.hillwillow = self.nixos-flake.lib.mkLinuxSystem {
          nixpkgs.hostPlatform = "x86_64-linux";
          imports = [
            ./hosts/core
            ./hosts/hillwillow

            ./modules/bluetooth.nix
            ./modules/desktop.nix
            ./modules/doas.nix
            ./modules/gamemode.nix
            ./modules/network.nix
            ./modules/nix.nix
            ./modules/nvidia.nix
            ./modules/plymouth.nix
            ./modules/sddm.nix
            ./modules/security.nix

            # TODO: move this to own folder
            ({pkgs, ...}: {
              # Common Users
              users.users.${mainUser} = {
                description = "Aidan Pinard";
                isNormalUser = true;
                shell = pkgs.fish;
                uid = 1000; # ensure that uid is stable for rollback
                extraGroups = [
                  "wheel"
                  "networkmanager"
                ];
              };
              home-manager.users.${mainUser} = {
                imports = [self.homeModules.default];
                home.stateVersion = "23.05";
              };
            })

            ({_}: {
              # if needed, expose inputs to home manager
              home-manager.extraSpecialArgs = {inherit inputs;};
            })
            # Setup home-manager in NixOS config
            self.nixosModules.home-manager
          ];
        };

        # home-manager configuration goes here.
        homeModules.default = {...}: {
          imports = [
            ./home/firefox
            ./home/fish.nix
            ./home/games
            ./home/git.nix
            ./home/gpg
            ./home/helix
            ./home/hyprland
            ./home/misc.nix
            ./home/mpv.nix
            ./home/obs.nix
            ./home/shell.nix
            ./home/ssh.nix
            ./home/starship.nix
            ./home/tofi.nix
            ./home/wezterm
            ./home/xdg.nix
            ./home/zellij
          ];
        };
      };
    };

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nixos-flake = {
      url = "github:srid/nixos-flake";
    };

    devenv.url = "github:cachix/devenv";

    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";

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

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.flake-parts.follows = "flake-parts";
    };

    helix = {
      url = "github:helix-editor/helix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
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
