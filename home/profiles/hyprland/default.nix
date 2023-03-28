{ pkgs, ... }: {
  home.packages = with pkgs; [
    wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # Use nixos version
    extraConfig = builtins.readFile ./hypr.conf;
  };
}
