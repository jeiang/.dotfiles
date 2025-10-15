{config, ...}: {
  # needed for sops
  systemd.user.services.hyprpanel.unitConfig.after = ["sops-nix.service"];
  programs.hyprpanel = {
    enable = true;
    systemd.enable = true;
    # dontAssertNotificationDaemons = true;
    settings = {
      wallpaper.enable = false;
      hyprpanel = {
        restartCommand = "systemctl restart --user hyprpanel.service";
      };
      bar = {
        layouts = {
          "*" = {
            left = [
              "dashboard"
              "workspaces"
              "media"
            ];
            middle = ["windowtitle"];
            right = [
              "cpu"
              "ram"
              "cputemp"
              "storage"
              "netstat"
              "volume"
              "microphone"
              "network"
              "bluetooth"
              "weather"
              "clock"
              "systray"
              "notifications"
            ];
          };
        };

        launcher.autoDetectIcon = true;
        workspaces.show_icons = true;
        clock.format = "%a %b %e %k:%M";
      };
      menus = {
        clock = {
          time = {
            military = true;
            hideSeconds = true;
          };
          weather = {
            unit = "imperial";
            location = "Port of Spain";
            # TODO: put this in sops
            key = config.sops.secrets."api_keys/hyprpanel/weather".path;
          };
        };
        dashboard = {
          directories.enabled = false;
          stats.enable_gpu = false;
          shortcuts.left = {
            shortcut1 = {
              command = "firefox";
              tooltip = "Firefox";
              icon = "";
            };
            shortcut2 = {
              command = "ghostty";
              tooltip = "Ghostty";
              icon = "";
            };
          };
        };
      };

      theme.bar.transparent = true;

      theme.font = {
        name = "JetBrains Mono";
        size = "16px";
      };
    };
  };
  sops.secrets."api_keys/hyprpanel/weather" = {};
}
