{self, ...}: {
  flake.nixosModules.hyprland = {
    config,
    pkgs,
    lib,
    ...
  }: let
    cursor = "rose-pine-hyprcursor";
    user = config.preferences.user.name;
    noctaliaExe = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.noctalia-shell;
  in {
    security.pam.services.hyprlock = {};

    programs = {
      hyprlock.enable = true;
      hyprland = {
        enable = true;
        withUWSM = true;
      };
    };

    services = {
      hypridle.enable = true;
      hypridle.package = self.packages.${pkgs.stdenv.hostPlatform.system}.hypridle;
      greetd = {
        enable = true;
        useTextGreeter = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --cmd 'uwsm start -- hyprland-uwsm.desktop'";
          };
        };
      };
    };

    environment.variables = rec {
      XCURSOR_SIZE = cursor;
      XCURSOR_THEME = 32;
      HYPRCURSOR_THEME = XCURSOR_SIZE;
      HYPRCURSOR_SIZE = XCURSOR_THEME;
    };

    hjem.users.${user}.files = {
      ".local/share/icons/${cursor}".source = "${pkgs.rose-pine-hyprcursor}/share/icons/${cursor}";
      ".config/hypr/hyprland.conf".text =
        # hypr
        ''
          ecosystem {
            no_update_news = true
          }

          debug {
            full_cm_proto = true
          }

          monitor = DP-1, 5120x1440@240, 0x0, 1
          monitor = ,preferred,auto,auto

          exec-once = ${noctaliaExe}
          exec-once = uwsm app -- ${lib.getExe pkgs.netbird-ui}

          $fileManager=uwsm app -- /nix/store/qkk4p7h4plf4vqmqa2q4xip2r3zwk4zy-dolphin-25.12.3/bin/dolphin
          $mainMod=SUPER
          $menu=/nix/store/vwjj9nsal2yn77pm1gqpay612q0grrmz-custom-noctalia/bin/noctalia-shell ipc call launcher
          $terminal=uwsm app -- /nix/store/ln9i1hs8v6rv57mzhgmm7d9pq7b5m6bf-ghostty-1.3.1/bin/ghostty

          permission=/nix/store/*/bin/xdg-desktop-portal-hyprland, screencopy, allow

          env=XCURSOR_SIZE,24
          env=HYPRCURSOR_SIZE,24

          general {
            allow_tearing=false
            border_size=2
            col.active_border=rgba(33ccffee) rgba(00ff99ee) 45deg
            col.inactive_border=rgba(595959aa)
            gaps_in=5
            gaps_out=10
            layout=dwindle
            resize_on_border=false
          }

          decoration {
            blur {
              enabled=true
              passes=2
              size=3
              vibrancy=0.169600
            }

            shadow {
              color=rgba(1a1a1aee)
              enabled=true
              range=4
              render_power=3
            }
            active_opacity=0.900000
            inactive_opacity=0.800000
            rounding=10
            rounding_power=2
          }

          animations {
            enabled=yes, please :)
            bezier=easeOutQuint,   0.23, 1,    0.32, 1
            bezier=easeInOutCubic, 0.65, 0.05, 0.36, 1
            bezier=linear,         0,    0,    1,    1
            bezier=almostLinear,   0.5,  0.5,  0.75, 1
            bezier=quick,          0.15, 0,    0.1,  1
            animation=global,        1,     10,    default
            animation=border,        1,     5.39,  easeOutQuint
            animation=windows,       1,     4.79,  easeOutQuint
            animation=windowsIn,     1,     4.1,   easeOutQuint, popin 87%
            animation=windowsOut,    1,     1.49,  linear,       popin 87%
            animation=fadeIn,        1,     1.73,  almostLinear
            animation=fadeOut,       1,     1.46,  almostLinear
            animation=fade,          1,     3.03,  quick
            animation=layers,        1,     3.81,  easeOutQuint
            animation=layersIn,      1,     4,     easeOutQuint, fade
            animation=layersOut,     1,     1.5,   linear,       fade
            animation=fadeLayersIn,  1,     1.79,  almostLinear
            animation=fadeLayersOut, 1,     1.39,  almostLinear
            animation=workspaces,    1,     1.94,  almostLinear, fade
            animation=workspacesIn,  1,     1.21,  almostLinear, fade
            animation=workspacesOut, 1,     1.94,  almostLinear, fade
            animation=zoomFactor,    1,     7,     quick
          }

          dwindle {
            preserve_split=true
            pseudotile=true
          }

          master {
            new_status=master
          }

          input {
            follow_mouse=1
            kb_layout=us
            numlock_by_default=true
            sensitivity=0
          }

          bind=$mainMod, T, exec, $terminal
          bind=$mainMod SHIFT, V, exec, $menu clipboard
          bind=$mainMod, E, exec, $fileManager
          bind=$mainMod, Space, exec, $menu toggle
          bind=$mainMod, V, togglefloating,
          bind=$mainMod SHIFT, F, fullscreen, 0
          bind=$mainMod, P, pseudo, # dwindle
          bind=$mainMod, J, togglesplit, # dwindle
          bind=$mainMod, Q, killactive,
          bind=$mainMod, M, exit,
          bind=$mainMod, left, movefocus, l
          bind=$mainMod, right, movefocus, r
          bind=$mainMod, up, movefocus, u
          bind=$mainMod, down, movefocus, d
          bind=$mainMod, 1, workspace, 1
          bind=$mainMod, 2, workspace, 2
          bind=$mainMod, 3, workspace, 3
          bind=$mainMod, 4, workspace, 4
          bind=$mainMod, 5, workspace, 5
          bind=$mainMod, 6, workspace, 6
          bind=$mainMod, 7, workspace, 7
          bind=$mainMod, 8, workspace, 8
          bind=$mainMod, 9, workspace, 9
          bind=$mainMod, 0, workspace, 10
          bind=$mainMod SHIFT, 1, movetoworkspace, 1
          bind=$mainMod SHIFT, 2, movetoworkspace, 2
          bind=$mainMod SHIFT, 3, movetoworkspace, 3
          bind=$mainMod SHIFT, 4, movetoworkspace, 4
          bind=$mainMod SHIFT, 5, movetoworkspace, 5
          bind=$mainMod SHIFT, 6, movetoworkspace, 6
          bind=$mainMod SHIFT, 7, movetoworkspace, 7
          bind=$mainMod SHIFT, 8, movetoworkspace, 8
          bind=$mainMod SHIFT, 9, movetoworkspace, 9
          bind=$mainMod SHIFT, 0, movetoworkspace, 10
          bind=$mainMod, S, togglespecialworkspace, magic
          bind=$mainMod SHIFT, S, movetoworkspace, special:magic
          bind=$mainMod, mouse_down, workspace, e+1
          bind=$mainMod, mouse_up, workspace, e-1

          bindel=,XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
          bindel=,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
          bindel=,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
          bindel=,XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

          bindm=$mainMod, mouse:272, movewindow
          bindm=$mainMod, mouse:273, resizewindow

          windowrule=match:class .*, suppress_event maximize
          windowrule=match:class ^(mpv)$, opacity 1.0 override
        '';
    };
  };
}
