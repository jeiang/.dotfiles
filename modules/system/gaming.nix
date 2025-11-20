{pkgs, ...}: {
  programs = {
    gamescope = {
      enable = true;
      capSysNice = false;
    };
    gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10;
        };

        # Warning: GPU optimisations have the potential to damage hardware
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          amd_performance_level = "high";
        };

        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
        };
      };
    };
    steam = {
      enable = true;
      extest.enable = true;
      protontricks.enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };
  };
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-cpp;
    extraRules = [
      {
        "name" = "gamescope";
        "nice" = -20;
      }
    ];
  };
}
