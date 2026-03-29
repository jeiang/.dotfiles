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
    terminal = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.terminal;
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

    environment.systemPackages = with pkgs; [
      rose-pine-hyprcursor
    ];

    environment.variables = rec {
      XCURSOR_SIZE = 32;
      XCURSOR_THEME = cursor;
      HYPRCURSOR_THEME = XCURSOR_THEME;
      HYPRCURSOR_SIZE = XCURSOR_SIZE;
    };

    hjem.users.${user}.files = {
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

          $fileManager=uwsm app -- ${lib.getExe' pkgs.kdePackages.dolphin "dolphin"}
          $mainMod=SUPER
          $menu=${noctaliaExe} ipc call launcher
          $terminal=uwsm app -- ${terminal}

          permission=${lib.getExe config.programs.hyprland.portalPackage}, screencopy, allow

          general {
            allow_tearing=false
            border_size=2
            col.active_border=rgba(33ccffee) rgba(00ff99ee) 45deg
            col.inactive_border=rgba(595959aa)
            gaps_in=5
            gaps_out=10
            layout=scrolling
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
          bind=$mainMod, Q, killactive,
          bind=$mainMod, M, exit,
          bind=$mainMod, left, movefocus, l
          bind=$mainMod, right, movefocus, r
          bind=$mainMod, up, movefocus, u
          bind=$mainMod, down, movefocus, d
          bind=$mainMod, K, movefocus, u
          bind=$mainMod, J, movefocus, d
          bind=$mainMod, H, movefocus, l
          bind=$mainMod, L, movefocus, r
          bind=$mainMod SHIFT, left, movewindow, l
          bind=$mainMod SHIFT, right, movewindow, r
          bind=$mainMod SHIFT, up, movewindow, u
          bind=$mainMod SHIFT, down, movewindow, d
          bind=$mainMod SHIFT, K, movewindow, u
          bind=$mainMod SHIFT, J, movewindow, d
          bind=$mainMod SHIFT, H, movewindow, l
          bind=$mainMod SHIFT, L, movewindow, r
          bind=$mainMod, P, layoutmsg, promote
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
          bind=$mainMod, code:59, workspace, -1
          bind=$mainMod, code:60, workspace, +1
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
          bind = $mainMod, R,submap,resize
          submap=resize
          bind = , right, resizeactive, 10 0
          bind = , left, resizeactive, -10 0
          bind = , up, resizeactive, 0 -10
          bind = , down, resizeactive, 0 10
          bind = , l, resizeactive, 10 0
          bind = , h, resizeactive, -10 0
          bind = , k, resizeactive, 0 -10
          bind = , j, resizeactive, 0 10
          bind = SHIFT, right, resizeactive, 50 0
          bind = SHIFT, left, resizeactive, -50 0
          bind = SHIFT, up, resizeactive, 0 -50
          bind = SHIFT, down, resizeactive, 0 50
          bind = SHIFT, l, resizeactive, 50 0
          bind = SHIFT, h, resizeactive, -50 0
          bind = SHIFT, k, resizeactive, 0 -50
          bind = SHIFT, j, resizeactive, 0 50
          submap=reset
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
