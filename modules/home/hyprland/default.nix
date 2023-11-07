{ pkgs, ... }: {
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = [
        ",preferred,auto,auto"
      ];
      env = [
        "XCURSOR_SIZE,24"
      ];

      input = {
        kb_layout = "us";
        follow_mouse = "1";
        numlock_by_default = "true";
        sensitivity = "0";
      };

      general = {
        gaps_in = 5;
        gaps_out = 20;
        border_size = 2;
        "col.active_border" = "rgba(33ccffee) rgba(00ff99ee) 45deg";
        "col.inactive_border" = "rgba(595959aa)";

        layout = "dwindle";

        allow_tearing = "false";
      };

      decoration = {
        rounding = "10";

        blur = {
          enabled = "true";
          size = "3";
          passes = "1";
        };

        drop_shadow = "true";
        shadow_range = "4";
        shadow_render_power = "3";
        "col.shadow" = "rgba(1a1a1aee)";
      };

      animations = {
        enabled = "yes";

        bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

        animation = [
          "windows, 1, 7, myBezier"
          "windowsOut, 1, 7, default, popin 80%"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 7, default"
          "workspaces, 1, 6, default"
        ];
      };

      dwindle = {
        pseudotile = "yes"; # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = "yes"; # you probably want this
      };

      master = {
        new_is_master = "true";
      };

      gestures = {
        workspace_swipe = false;
      };

      bind = [
        # Manipulate windows
        "SUPER, Q, killactive,"
        "SUPER, F10, exit,"
        "SUPER, F, togglefloating,"
        "SUPER, P, pseudo," # dwindle
        "SUPER, S, togglesplit," # dwindle

        # Move focus with mainMod + arrow keys/hjkl
        "SUPER, left, movefocus, l"
        "SUPER, H, movefocus, l"
        "SUPER, right, movefocus, r"
        "SUPER, L, movefocus, r"
        "SUPER, up, movefocus, u"
        "SUPER, K, movefocus, u"
        "SUPER, down, movefocus, d"
        "SUPER, J, movefocus, d"

        # Switch workspaces with mainMod + [0-9]
        "SUPER, 1, workspace, 1"
        "SUPER, 2, workspace, 2"
        "SUPER, 3, workspace, 3"
        "SUPER, 4, workspace, 4"
        "SUPER, 5, workspace, 5"
        "SUPER, 6, workspace, 6"
        "SUPER, 7, workspace, 7"
        "SUPER, 8, workspace, 8"
        "SUPER, 9, workspace, 9"
        "SUPER, 0, workspace, 10"

        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "SUPER SHIFT, 1, movetoworkspace, 1"
        "SUPER SHIFT, 2, movetoworkspace, 2"
        "SUPER SHIFT, 3, movetoworkspace, 3"
        "SUPER SHIFT, 4, movetoworkspace, 4"
        "SUPER SHIFT, 5, movetoworkspace, 5"
        "SUPER SHIFT, 6, movetoworkspace, 6"
        "SUPER SHIFT, 7, movetoworkspace, 7"
        "SUPER SHIFT, 8, movetoworkspace, 8"
        "SUPER SHIFT, 9, movetoworkspace, 9"
        "SUPER SHIFT, 0, movetoworkspace, 10"

        # Scroll through existing workspaces with mainMod + scroll
        "SUPER, mouse_down, workspace, e+1"
        "SUPER, mouse_up, workspace, e-1"
      ] ++ (
        let
          firefox = "${pkgs.firefox}/bin/firefox";
          wezterm = "${pkgs.wezterm}/bin/wezterm";
          grimblast = "${pkgs.grimblast}/bin/grimblast";
        in
        [
          # Launch Apps
          "SUPER, return, exec, ${wezterm}"
          "SUPER, W, exec, ${firefox}"

          ## App Launcher w/ desktop files
          # TODO: implement tofi
          # "SUPER, R, exec, tofi-drun | xargs hyprctl dispatch exec --"
          # "SUPER SHIFT, R, exec, tofi-run | xargs hyprctl dispatch exec --"

          # Copy & Paste Menu
          # FIXME: tofi shows a replacement character for the tab
          # "SUPER, V, exec, ${pkgs.cliphist}/bin/cliphist list | tofi | ${pkgs.cliphist}/bin/cliphist decode | wl-copy"

          # Shortcuts
          ## Screenshot
          "SUPER SHIFT, S, exec, ${grimblast} --notify copysave area"
        ]
      );

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      binde = [
        # Audio using wireplumber
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"
      ];

      exec-once =
        let
          wl-clipboard = "${pkgs.wl-clipboard}/bin/wl-paste";
          cliphist = "${pkgs.cliphist}/bin/cliphist";
          mako = "${pkgs.mako}/bin/mako";
        in
        [
          "${mako}"
          "${wl-clipboard} --type text --watch ${cliphist} store" #Stores only text data
          "${wl-clipboard} --type image --watch ${cliphist} store" #Stores only image data
        ];
    };
  };

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
