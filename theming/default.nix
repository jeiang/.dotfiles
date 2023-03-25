# Theme stuff
{ inputs, outputs, lib, config, pkgs, ... }:
let
  image = pkgs.fetchurl {
    url = "https://files.catbox.moe/4a51fr.png";
    sha256 = "sha256-1g16QYYZ12fqdKV59N+wMaMU8kM+maO3ygud7YGD+yA=";
  };
in
{
  stylix = {
    inherit image;
    polarity = "dark";
    base16Scheme = ./theme.yaml;
    fonts = rec {
      serif = sansSerif;
      sansSerif = {
        name = "Overpass";
        package = pkgs.overpass;
      };
      monospace = {
        name = "JetBrainsMono Nerd Font Mono";
        package = pkgs.nerdfonts.override {
          fonts = [ "JetBrainsMono" ];
        };
      };
    };
  };
}
