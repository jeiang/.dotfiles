{ inputs, outputs, lib, config, pkgs, ... }: {

  programs.mcfly = {
    enable = true;
    enableFishIntegration = true;
    fuzzySearchFactor = 2;
  };
}
