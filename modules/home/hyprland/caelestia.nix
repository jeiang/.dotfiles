{
  wayland.windowManager.hyprland = {
    settings = {
      # Misc
      "$kbSession" = "Ctrl+Alt, Delete";
      "$kbClearNotifs" = "Ctrl+Alt, C";
      "$kbShowPanels" = "Super, K";
      "$kbLock" = "Super, L";
      "$kbRestoreLock" = "Super+Alt, L";

      bind = [
        # Misc
        "$kbSession, global, caelestia:session"
        "$kbShowPanels, global, caelestia:showall"
        "$kbLock, global, caelestia:lock"
      ];

      bindl = [
        # Misc
        "$kbClearNotifs, global, caelestia:clearNotifs"

        # Restore lock
        "$kbRestoreLock, exec, caelestia shell -d"
        "$kbRestoreLock, global, caelestia:lock"

        # Media
        "Ctrl+Super, Space, global, caelestia:mediaToggle"
        ", XF86AudioPlay, global, caelestia:mediaToggle"
        ", XF86AudioPause, global, caelestia:mediaToggle"
        "Ctrl+Super, Equal, global, caelestia:mediaNext"
        ", XF86AudioNext, global, caelestia:mediaNext"
        "Ctrl+Super, Minus, global, caelestia:mediaPrev"
        ", XF86AudioPrev, global, caelestia:mediaPrev"
        ", XF86AudioStop, global, caelestia:mediaStop"
      ];

      # Kill/restart
      bindr = [
        "Ctrl+Super+Shift, R, exec, systemctl stop --user caelestia.service"
        "Ctrl+Super+Alt, R, exec, systemctl restart --user caelestia.service"
      ];
    };
  };
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
          audio = ["pwvucontrol"];
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
      services.weatherLocation = "10.671067,-61.521206";
      osd = {
        enableBrightness = false;
        enableMicrophone = true;
      };
      utilities = {
        vpn.enabled = true;
        toasts.nowPlaying = true;
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
