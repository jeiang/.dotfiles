{
  flake-parts-lib,
  self,
  inputs,
  lib,
  ...
}: let
  inherit (flake-parts-lib) importApply;
in {
  flake.nixosModules = {
    nix = importApply ./system/nix.nix {
      localFlake = self;
      inherit inputs lib;
    };
    sops = import ./system/sops;
    shared = import ./system/shared-config.nix;
    home-manager = import ./system/home-manager.nix;
    attic = import ./system/attic.nix;
    caddy = import ./system/caddy.nix;
    blocky = import ./system/blocky.nix;
    netbird = import ./system/netbird.nix;
    website = import ./system/website.nix;
    authelia = import ./system/authelia.nix;
    security = import ./system/security.nix;
    hyprland = import ./system/hyprland.nix;
  };
  flake.homeModules = {
    fish = import ./home/fish.nix;
    attic = import ./home/attic.nix;
    git = import ./home/git.nix;
    helix = importApply ./home/helix {
      localFlake = self;
      inherit inputs lib;
    };
    starship = import ./home/starship;
    zellij = import ./home/zellij;
    ssh = import ./home/ssh.nix;
    hyprland = import ./home/hyprland;
    graphical = import ./home/graphical.nix;
  };
}
