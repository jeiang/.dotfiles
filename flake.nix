{
  description = "My NixOS config.";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    extra-substituters = [
      "https://nrdxp.cachix.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://jeiang.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "jeiang.cachix.org-1:Ax2onCzp6V74ORnjlTAbZsDmlLeMMzDOzzcC2qHfJKg="
    ];
  };

  inputs = {
    blank.url = "github:divnix/blank";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    digga.url = "github:divnix/digga";
    digga.inputs.nixpkgs.follows = "nixpkgs";
    digga.inputs.nixlib.follows = "nixpkgs";
    digga.inputs.home-manager.follows = "home-manager";
    digga.inputs.darwin.follows = "blank";
    digga.inputs.deploy.follows = "blank";
    digga.inputs.flake-compat.follows = "blank";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    nvfetcher.url = "github:berberman/nvfetcher";
    nvfetcher.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/NUR";

    base16.url = "github:SenchoPens/base16.nix";
    base16.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.base16.follows = "base16";
    stylix.inputs.home-manager.follows = "home-manager";

    hyprland.url = "github:hyprwm/Hyprland";
    hyprpaper.url = "github:hyprwm/hyprpaper";
    hyprpaper.inputs.nixpkgs.follows = "nixpkgs";
    hyprcontrib.url = "github:hyprwm/contrib";
    hyprcontrib.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    { self
    , nixpkgs
    , nixos-hardware
    , home-manager
    , digga
    , agenix
    , nvfetcher
    , nur
    , stylix
    , base16
    , hyprland
    , hyprpaper
    , hyprcontrib
    , impermanence
    , ...
    } @ inputs:
    digga.lib.mkFlake
      {
        inherit self inputs;

        channelsConfig = { allowUnfree = true; };

        channels = {
          nixpkgs = {
            imports = [ (digga.lib.importOverlays ./overlays) ];
            overlays = [ nur.overlay ];
          };
        };

        lib = import ./lib { lib = digga.lib // nixpkgs.lib; };

        sharedOverlays = [
          (final: prev: {
            __dontExport = true;
            lib = prev.lib.extend (lfinal: lprev: {
              our = self.lib;
            });
          })

          agenix.overlays.default
          nvfetcher.overlays.default
          hyprpaper.overlays.default
          hyprcontrib.overlays.default
          nur.overlay

          (import ./pkgs)
        ];

        nixos = {
          imports = [ (digga.lib.importHosts ./hosts) ];
          importables = rec {
            profiles =
              digga.lib.rakeLeaves ./profiles
              // {
                users = digga.lib.rakeLeaves ./users;
              };
            suites = with profiles; rec {
              base = [ nixos cachix users.root ];
              bootable-iso = base ++ [ users.nixos ];
              laptop = [ profiles.hyprland profiles.stylix users.aidanp btrfs-optin-persistence plymouth swap-partition ] ++ base;
            };
          };
          hostDefaults = {
            system = "x86_64-linux";
            channelName = "nixpkgs";
            imports = [ (digga.lib.importExportableModules ./modules) ];
            modules = [
              { lib.our = self.lib; }
              digga.nixosModules.bootstrapIso
              digga.nixosModules.nixConfig
              home-manager.nixosModules.home-manager
              agenix.nixosModules.age
              hyprland.nixosModules.default
              stylix.nixosModules.stylix
              base16.nixosModule
              impermanence.nixosModule
            ];
          };
          hosts = {
            hillwillow = {
              modules = [
                nixos-hardware.nixosModules.asus-battery
              ];
            };
          };
        };

        home = {
          imports = [ (digga.lib.importExportableModules ./home/modules) ];
          modules = [
            hyprland.homeManagerModules.default
            base16.homeManagerModule
          ];
          importables = rec {
            profiles = digga.lib.rakeLeaves ./home/profiles;
            suites = with profiles; rec {
              base = [ direnv git xdg ];
              terminal = [ bottom fish gpg helix nushell terminal-utils ssh starship zellij ];
              gui-stuff = [ wezterm firefox ];
              wm = [ profiles.hyprland eww tofi cliphist ];
              full = [ misc-packages mpv obs ] ++ base ++ terminal ++ wm ++ gui-stuff;
            };
          };
          users = {
            nixos = { suites, ... }: {
              imports = suites.base ++ suites.terminal;

              home.stateVersion = "23.05";
            };
            aidanp = { suites, ... }: {
              imports = suites.full;

              # Nicely reload system units when changing configs if dbus is enabled
              systemd.user.startServices =
                let
                  dbus-enabled = self.outputs.nixosConfigurations.hillwillow.config.services.dbus.enable;
                in
                if dbus-enabled then "sd-switch" else "suggest";

              home.stateVersion = "23.05";
            };
          };
        };

        devshell = ./shell;

        homeConfigurations = digga.lib.mkHomeConfigurations self.nixosConfigurations;
      } // {
      # Manually skip checks for darwin. I have no plans to use mac
      checks.x86_64-darwin = { };
    };
}
