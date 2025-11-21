{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hypridle.nix
    ./hyprpanel.nix
    ./hyprpaper.nix
    ./hyprsunset.nix
    # ./swaync.nix
    ./walker.nix
  ];
  gtk = {
    enable = true;
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
  };
  home = {
    packages = with pkgs; [
      # for screensharing with xwayland apps
      kdePackages.xwaylandvideobridge
    ];
    pointerCursor = {
      enable = true;
      name = "rose-pine-hyprcursor";
      package = pkgs.rose-pine-hyprcursor;
      gtk.enable = true;
      x11.enable = true;
      hyprcursor.enable = true;
    };
    sessionVariables = {
      AQ_DRM_DEVICES = lib.mkDefault "/dev/dri/egpu:/dev/dri/igpu";
    };
  };
  programs.hyprshot.enable = true;
  services = {
    hyprpolkitagent.enable = true;
    clipse.enable = true;
  };
  xdg.configFile."uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";

  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;
    systemd.enable = false;
    settings = {
      ecosystem = {
        no_update_news = true;
      };
      debug = {
        full_cm_proto = true;
      };
      monitor = [
        # TODO: find a way to make this machine specific
        "DP-1, 5120x1440@240, 0x0, 1"
        ",preferred,auto,auto"
      ];
      "$terminal" = "uwsm app -- ${config.programs.ghostty.package}/bin/ghostty";
      "$fileManager" = "uwsm app -- ${config.programs.ghostty.package}/bin/ghostty -e ${config.programs.yazi.package}/bin/yazi";
      "$menu" = "uwsm app -- ${config.services.walker.package}/bin/walker";
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
      ];
      permission = [
        "/nix/store/*/bin/xdg-desktop-portal-hyprland, screencopy, allow"
      ];
      general = {
        gaps_in = "5";
        gaps_out = "20";
        border_size = "2";
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
        resize_on_border = "false";
        allow_tearing = "false";
        layout = "dwindle";
      };
      decoration = {
        rounding = 10;
        rounding_power = 2;
        active_opacity = 0.9;
        inactive_opacity = 0.8;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
          vibrancy = 0.1696;
        };
      };
      animations = {
        enabled = "yes, please :)";
        bezier = [
          #        NAME,           X0,   Y0,   X1,   Y1
          "easeOutQuint,   0.23, 1,    0.32, 1"
          "easeInOutCubic, 0.65, 0.05, 0.36, 1"
          "linear,         0,    0,    1,    1"
          "almostLinear,   0.5,  0.5,  0.75, 1"
          "quick,          0.15, 0,    0.1,  1"
        ];
        animation = [
          #NAME,          ONOFF, SPEED, CURVE,        [STYLE]
          "global,        1,     10,    default"
          "border,        1,     5.39,  easeOutQuint"
          "windows,       1,     4.79,  easeOutQuint"
          "windowsIn,     1,     4.1,   easeOutQuint, popin 87%"
          "windowsOut,    1,     1.49,  linear,       popin 87%"
          "fadeIn,        1,     1.73,  almostLinear"
          "fadeOut,       1,     1.46,  almostLinear"
          "fade,          1,     3.03,  quick"
          "layers,        1,     3.81,  easeOutQuint"
          "layersIn,      1,     4,     easeOutQuint, fade"
          "layersOut,     1,     1.5,   linear,       fade"
          "fadeLayersIn,  1,     1.79,  almostLinear"
          "fadeLayersOut, 1,     1.39,  almostLinear"
          "workspaces,    1,     1.94,  almostLinear, fade"
          "workspacesIn,  1,     1.21,  almostLinear, fade"
          "workspacesOut, 1,     1.94,  almostLinear, fade"
          "zoomFactor,    1,     7,     quick"
        ];
      };
      dwindle = {
        pseudotile = true; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true; # You probably want this
      };
      master = {
        new_status = "master";
      };
      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        numlock_by_default = true;
      };
      "$mainMod" = "SUPER"; # Sets "Windows" key as main modifier
      bind = [
        # Apps
        "$mainMod, T, exec, $terminal"
        "$mainMod SHIFT, V, exec, $terminal --class=savedra1.clipse -e clipse"
        "$mainMod, E, exec, $fileManager"
        "$mainMod, Space, exec, $menu"
        # Misc Controls
        "$mainMod, V, togglefloating,"
        "$mainMod, P, pseudo, # dwindle"
        "$mainMod, J, togglesplit, # dwindle"
        "$mainMod, Q, killactive,"
        "$mainMod, M, exit,"
        # Move focus with mainMod + arrow keys
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"
        # Switch workspaces with mainMod + [0-9]
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"
        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"
        # Example special workspace (scratchpad)
        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"
        # Scroll through existing workspaces with mainMod + scroll
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
      ];
      bindm = [
        # Move/resize windows with mainMod + LMB/RMB and dragging
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];
      bindel = [
        # Laptop multimedia keys for volume and LCD brightness
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
        ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
      ];
      bindl = [
        # Requires playerctl
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
      ];
      windowrule = [
        # Ignore maximize requests from apps. You'll probably like this.
        "suppressevent maximize, class:.*"
        # Fix some dragging issues with XWayland
        "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
        # Rules for xwaylandvideobridge from https://wiki.hypr.land/Useful-Utilities/Screen-Sharing/#xwayland
        "opacity 0.0 override, class:^(xwaylandvideobridge)$"
        "noanim, class:^(xwaylandvideobridge)$"
        "noinitialfocus, class:^(xwaylandvideobridge)$"
        "maxsize 1 1, class:^(xwaylandvideobridge)$"
        "noblur, class:^(xwaylandvideobridge)$"
        "nofocus, class:^(xwaylandvideobridge)$"
        # Clipse Rules
        "float, class:(savedra1.clipse)"
        "size 622 652, class:(savedra1.clipse)"
        "stayfocused, class:(savedra1.clipse)"
      ];
    };
  };
}
