{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.navi = {
    enable = true;
    enableFishIntegration = true;
    settings = { cheats = { paths = [ "~/Documents/Cheats" ]; }; };
  };
}
