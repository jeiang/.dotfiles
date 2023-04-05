{ pkgs, ... }:
let
  image = pkgs.fetchurl {
    url = "https://files.catbox.moe/4a51fr.png";
    sha256 = "sha256-1g16QYYZ12fqdKV59N+wMaMU8kM+maO3ygud7YGD+yA=";
  };
  base16-schemes = pkgs.fetchFromGitHub {
    owner = "tinted-theming";
    repo = "base16-schemes";
    rev = "42d74711418db38b08575336fc03f30bd3799d1d";
    sha256 = "sha256-ZSul9NpLbRgMIla+IIijFwGWZhx+ShfY2KzNicLG8jY=";
  };
in
{
  stylix = {
    inherit image;
    polarity = "dark";
    base16Scheme = "${base16-schemes}/ayu-dark.yaml";
    fonts = rec {
      serif = sansSerif;
      sansSerif = {
        name = "Ubuntu";
        package = pkgs.ubuntu_font_family;
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
