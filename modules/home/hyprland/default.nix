{pkgs, ...}: let
  hyprconf = ''
    source = ${./hyprland.conf}

    exec-once = ${pkgs.mako}/bin/mako
    # exec-once = hyprpaper
    exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store #Stores only text data
    exec-once = ${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store #Stores only image data

    $mainMod = SUPER

    # Launch Apps
    bind = $mainMod, return, exec, ${pkgs.alacritty}/bin/alacritty
    # See https://github.com/wez/wezterm/issues/4483
    # bind = $mainMod, return, exec, ${pkgs.wezterm}/bin/wezterm
    bind = $mainMod, W, exec, ${pkgs.firefox}/bin/firefox
    # bind = $mainMod, R, exec, tofi-drun | xargs hyprctl dispatch exec --
    # bind = $mainMod SHIFT, R, exec, tofi-run | xargs hyprctl dispatch exec --

    # Copy & Paste Menu
    # FIXME: tofi shows a replacement character for the tab
    # bind = SUPER, V, exec, ${pkgs.cliphist}/bin/cliphist list | tofi | ${pkgs.cliphist}/bin/cliphist decode | wl-copy

    # Shortcuts
    ## Screenshot
    bind = $mainMod SHIFT, S, exec, grimblast --notify copysave area

    # Audio using wireplumber
    binde=, XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    binde=, XF86AudioLowerVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-

    # Brightness change
    # bindle=, XF86MonBrightnessUp, exec, brightnessctl set 5%+
    # bindle=, XF86MonBrightnessDown, exec, brightnessctl set 5%-

  '';
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = null; # Use nixos version
    extraConfig = hyprconf;
  };

  # TODO: add swww: https://github.com/Horus645/swww
  # TODO: remove from here and move to wayland module + direct insert to conf file
  home.packages = with pkgs; [
    grim
    slurp
    grimblast
    brightnessctl
    hyprpaper
    grimblast
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
