{ pkgs, lib, ... }:
let
  colors = { };
  overrides = { };
in
{
  home.packages = with pkgs; [
    eww-wayland

    (nerdfonts.override {
      fonts = [ "JetBrainsMono" ];
    })
    font-awesome # 6, not included in nf
    brightnessctl
    libnotify
    socat
  ];

  # EWW bar
  xdg.configFile."eww/eww.yuck".text = lib.our.replaceStrings overrides ./bar/eww.yuck;
  xdg.configFile."eww/eww.scss".text = lib.our.replaceStrings colors ./bar/eww.scss;
  xdg.configFile."eww/scripts".source = ./bar/scripts;
}
