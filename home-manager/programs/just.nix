{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.just = {
    enable = true;
    enableFishIntegration = true;
  };
}
