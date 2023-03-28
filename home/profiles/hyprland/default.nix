{ pkgs, lib, ... }:
let
  keys = {
    "{{mako}}" = "${pkgs.mako}/bin/mako";
    "{{polkit}}" = "${pkgs.libsForQt5.polkit-kde-agent}/libexec/polkit-kde-authentication-agent-1";
  };
  extraConfig = lib.our.replaceStrings keys ./hypr.conf;
in
{
  home.packages = with pkgs; [
    wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # Use nixos version
    inherit extraConfig;
  };

  # Notifications
  services.mako = {
    enable = true;
    defaultTimeout = 5000; # disappears after 5 secs
  };
}
