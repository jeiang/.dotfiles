{ pkgs, lib, config, ... }:
let
  monitor-connect-script = pkgs.writeScriptBin "handle_monitor_connect" ''
    function handle {
      if [[ $${1:0:12} == "monitoradded" ]]; then
        hyprctl dispatch moveworkspacetomonitor "1 1"
        hyprctl dispatch moveworkspacetomonitor "2 1"
        hyprctl dispatch moveworkspacetomonitor "3 1"
        hyprctl dispatch moveworkspacetomonitor "4 1"
        hyprctl dispatch moveworkspacetomonitor "5 1"
      fi
    }

    ${pkgs.socat}/bin/socat - "UNIX-CONNECT:$(readlink -f /tmp/hypr/*/.socket2.sock)" | while read line; do handle $line; done
  '';
  hypr-conf-keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{hyprpaper}}" = "${pkgs.hyprpaper}/bin/hyprpaper";
    "{{wezterm}}" = "${pkgs.wezterm}/bin/wezterm";
    "{{firefox}}" = "${pkgs.firefox}/bin/firefox";
    "{{grimblast}}" = "${pkgs.grimblast}/bin/grimblast";
    "{{eww}}" = "${pkgs.eww-wayland}/bin/eww";
    "{{connect-monitor}}" = "${monitor-connect-script}/bin/handle-monitor-connect";
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

  # cursor theme
  home.pointerCursor = {
    gtk.enable = true;
    package = pkgs.nur.repos.ruixi-rebirth.catppuccin-cursors;
    name = "Catppuccin-cursor";
  };
}
