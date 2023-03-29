{ pkgs, lib, config, ... }:
let
  screenshot-script = pkgs.writeScriptBin "screenshot" ''
    # xdg wack so...
    # normally grim $(xdg-user-dir PICTURES)/$(date +'%s_grim.png')
    mkdir -p ~/Pictures
    file=~/Pictures/$(date +'screenshot_%Y-%d-%m-%T.png')
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$file"
    cat $file | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
  hypr-conf-keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{hyprpaper}}" = "${pkgs.hyprpaper}/bin/hyprpaper";
    "{{wezterm}}" = "${pkgs.wezterm}/bin/wezterm";
    "{{firefox}}" = "${pkgs.firefox}/bin/firefox";
    "{{screenshot}}" = "${screenshot-script}/bin/screenshot";
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
  ];

  xdg.configFile."hypr/hyprpaper.conf" = {
    onChange = ''
      pkill hyprpaper
      hyprpaper 2> /dev/null > /dev/null &
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
