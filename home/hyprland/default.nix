{
  pkgs,
  lib,
  ...
}: let
  # TODO: just concat hyprpaper.conf with a string here
  hypr-conf-keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{hyprpaper}}" = "${pkgs.hyprpaper}/bin/hyprpaper";
    "{{wezterm}}" = "${pkgs.wezterm}/bin/wezterm";
    "{{firefox}}" = "${pkgs.firefox}/bin/firefox";
    "{{grimblast}}" = "${pkgs.grimblast}/bin/grimblast";
    "{{eww}}" = "${pkgs.eww-wayland}/bin/eww";
    "{{wl-paste}}" = "${pkgs.wl-clipboard}/bin/wl-paste";
    "{{cliphist}}" = "${pkgs.cliphist}/bin/cliphist";
  };
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # Use nixos version
    extraConfig = lib.our.replaceStrings hypr-conf-keys ./hyprland.conf;
  };

  # TODO: add swww: https://github.com/Horus645/swww
  home.packages = with pkgs; [
    wl-clipboard
    grim
    slurp
    grimblast
    brightnessctl
  ];

  # Notifications
  services.mako = {
    enable = true;
    defaultTimeout = 5000; # disappears after 5 secs
  };

  # cursor theme
  home.pointerCursor = {
    gtk.enable = true;
    package = pkgs.vanilla-dmz;
    name = "Vanilla-DMZ";
  };
}
