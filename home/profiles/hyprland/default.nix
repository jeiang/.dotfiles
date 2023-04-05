{ pkgs, lib, config, ... }:
let
  hypr-conf-keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{hyprpaper}}" = "${pkgs.hyprpaper}/bin/hyprpaper";
    "{{wezterm}}" = "${pkgs.wezterm}/bin/wezterm";
    "{{firefox}}" = "${pkgs.firefox}/bin/firefox";
    "{{grimblast}}" = "${pkgs.grimblast}/bin/grimblast";
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
    grim
    slurp
    grimblast
    brightnessctl
  ];

  xdg.configFile."hypr/hyprpaper.conf" = {
    # Reload hyprpaper
    onChange = ''
      pkill hyprpaper
      log=$(mktemp -q -t hyprpaper-XXXXXX.log)
      err=$(mktemp -q -t hyprpaper-errors-XXXXXX.log)
      hyprpaper 2> "$log" > "$err" &
      disown
    '';
    text = lib.our.replaceStrings hyprpaper-conf-keys ./hyprpaper.conf;
  };

  # Notifications
  services.mako = {
    enable = true;
    defaultTimeout = 5000; # disappears after 5 secs
  };
}
