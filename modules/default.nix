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
  };
  flake.homeModules = {
    fish = import ./home/fish.nix;
    git = import ./home/git.nix;
    helix = importApply ./home/helix {
      localFlake = self;
      inherit inputs lib;
    };
    starship = import ./home/starship;
    zellij = import ./home/zellij;
    ssh = import ./home/ssh.nix;
  };
}
