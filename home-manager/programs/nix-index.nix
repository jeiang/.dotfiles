{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };
}
