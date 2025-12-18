{
  programs.caelestia = {
    enable = true;
    systemd = {
      enable = true;
    };
    settings = {
      general = {
        apps = {
          # TODO: somehow pull this from a config
          terminal = ["ghostty"];
          explorer = ["yazi"];
        };
        # Hypridle handles this
        idle.timeouts = [
          {
            timeout = 900;
            idleAction = "lock";
          }
          {
            timeout = 1200;
            idleAction = "dpms off";
            returnAction = "dpms on";
          }
          {
            # sleep if idle for 6 hours
            timeout = 21600;
            idleAction = ["systemctl" "suspend"];
          }
        ];
      };
      background.desktopClock.enabled = true;
      bar.status = {
        showAudio = true;
        showBattery = false;
      };
      osd = {
        enableBrightness = false;
        enableMicrophone = true;
      };
      paths = {
        wallpaperDir = "~/Pictures/Wallpapers";
      };
    };
    cli = {
      enable = true; # Also add caelestia-cli to path
      settings = {
        theme.enableGtk = false;
      };
    };
  };
}
