{ pkgs, lib, config, ... }:
let
  hypr-conf-keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{hyprpaper}}" = "${pkgs.hyprpaper}/bin/hyprpaper";
  };
  hyprpaper-conf-keys = {
    "{{wallpaper}}" = "${config.stylix.image}";
  };
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # Use nixos version
    extraConfig = lib.our.replaceStrings hypr-conf-keys ./hyprland.conf;
  };

  home.packages = with pkgs; [
    wl-clipboard
    hyprpaper
  ];

  xdg.configFile."hypr/hyprpaper.conf" = {
    # TODO: hyprctl hyprpaper ??reload??
    onChange = ''
    '';
    text = lib.our.replaceStrings hyprpaper-conf-keys ./hyprpaper.conf;
  };

  # Notifications
  services.mako = {
    enable = true;
    defaultTimeout = 5000; # disappears after 5 secs
  };
}
