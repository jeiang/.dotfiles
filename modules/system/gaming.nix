{pkgs, ...}: {
  services.udev.packages = let
    name = "99-boxflat.rules";
    gpu-rules = pkgs.writeText name ''
      # Add uaccess tag to every Moza (Gudsen) ttyACM device so a user can easily access it
      # without being added to the uucp group. This in turn will make it so EVERY user
      # can access these devices
      SUBSYSTEM=="tty", KERNEL=="ttyACM*", ATTRS{idVendor}=="346e", ACTION=="add", MODE="0666", TAG+="uaccess"

      # Add uaccess tag to uinput devices to create virtual joysticks
      SUBSYSTEM=="misc", KERNEL=="uinput", OPTIONS+="static_node=uinput", TAG+="uaccess"
    '';
    symlink-drv = pkgs.stdenv.mkDerivation {
      name = "boxflat-rules";
      phases = ["installPhase"];

      installPhase = ''
        mkdir -p $out/lib/udev/rules.d
        cp ${gpu-rules} $out/lib/udev/rules.d/${name}
      '';
    };
  in [
    symlink-drv
  ];
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
