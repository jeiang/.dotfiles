{
  sops = import ./sops.nix;
  nix = import ./nix.nix;
  home-manager = ./home-manager.nix;
}
