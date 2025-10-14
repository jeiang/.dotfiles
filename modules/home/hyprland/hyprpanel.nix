{
  programs.hyprpanel = {
    settings = {
      layout = {
        bar.layouts = {
          "0" = {
            left = ["dashboard" "workspaces"];
            middle = ["media"];
            right = ["volume" "systray" "notifications"];
          };
        };
      };
      bar = {
        launcher.autoDetectIcon = true;
        workspaces.show_icons = true;
      };
      menus = {
        clock = {
          time = {
            military = true;
            hideSeconds = true;
          };
          weather.unit = "imperial";
        };
        dashboard = {
          directories.enabled = false;
          stats.enable_gpu = true;
        };
      };
      theme = {
        bar.transparent = true;

        font = {
          name = "CaskaydiaCove NF";
          size = "16px";
        };
      };
    };
  };
}
