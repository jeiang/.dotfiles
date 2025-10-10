{
  flake.nixosModules = {
    nix = import ./system/nix.nix;
    sops = import ./system/sops;
    shared = import ./system/shared-config.nix;
    home-manager = import ./system/home-manager.nix;
  };
  flake.homeModules = {
    fish = import ./home/fish.nix;
    git = import ./home/git.nix;
    helix = import ./home/helix;
    starship = import ./home/starship;
    zellij = import ./home/zellij;
    ssh = import ./home/ssh.nix;
  };
}
