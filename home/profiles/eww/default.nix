{ pkgs, lib, ... }:
let
  overrides = { };
in
{
  # dont use this

  home.packages = with pkgs; [
    eww-wayland

    (nerdfonts.override {
      fonts = [ "JetBrainsMono" ];
    })
    font-awesome # 6, not included in nf
  ];

  # EWW bar
  xdg.configFile."eww/bar/eww.yuck".text = lib.replaceStrings overrides ./eww/eww.yuck;
  xdg.configFile."eww/bar/eww.scss".text = lib.replaceStrings overrides ./eww/eww.scss;
}
