{
  flake.nixosModules.gaming = {
    config,
    pkgs,
    lib,
    ...
  }: let
    user = config.preferences.user.name;
  in {
    environment.systemPackages = with pkgs; [
      boxflat
      mangohud
      (prismlauncher.override {
        # Add binary required by some mod
        additionalPrograms = [ffmpeg];

        # Change Java runtimes available to Prism Launcher
        jdks = [
          graalvmPackages.graalvm-ce
          zulu8
          zulu17
          zulu
        ];
      })
    ];
    hjem.users.${user}.files.".config/MangoHud/MangoHud.conf".text = ''
      legacy_layout=false
      background_alpha=0.6
      round_corners=0
      background_alpha=0.6
      background_color=000000
      font_size=24
      text_color=FFFFFF
      position=top-left
      pci_dev=0:03:00.0
      table_columns=3
      gpu_text=GPU
      gpu_stats
      gpu_load_change
      gpu_load_value=50,90
      gpu_load_color=FFFFFF,FFAA7F,CC0000
      throttling_status
      gpu_core_clock
      gpu_temp
      gpu_power
      gpu_color=2E9762
      cpu_text=CPU
      cpu_stats
      cpu_load_change
      cpu_load_value=50,90
      cpu_load_color=FFFFFF,FFAA7F,CC0000
      cpu_mhz
      cpu_temp
      cpu_power
      cpu_color=2E97CB
      vram
      vram_color=AD64C1
      vram_color=AD64C1
      ram
      ram_color=C26693
      fps
      fps_metrics=avg,0.01
      frame_timing
      frametime_color=FA8000
      fps_limit_method=late
      toggle_fps_limit=Shift_L+F1
      fps_limit=0
      fps_color_change
      fps_color=B22222,FDFD09,39F900
      fps_value=30,60
      output_folder=/home/aidanp
      log_duration=30
      autostart_log=0
      log_interval=100
      toggle_logging=Shift_L+F2
      blacklist=pamac-manager,lact,ghb,bitwig-studio,ptyxis,yumex
    '';
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
    in [
      (pkgs.stdenv.mkDerivation {
        inherit name;
        phases = ["installPhase"];

        installPhase = ''
          mkdir -p $out/lib/udev/rules.d
          cp ${gpu-rules} $out/lib/udev/rules.d/${name}
        '';
      })
    ];
    programs = {
      gamescope.enable = true;
      gamemode = {
        enable = true;
        settings = {
          general.renice = 10;
          # Warning: GPU optimisations have the potential to damage hardware
          gpu = {
            apply_gpu_optimisations = "accept-responsibility";
            gpu_device = 0;
            amd_performance_level = "high";
          };
          custom = {
            start = "${lib.getExe pkgs.libnotify} 'GameMode started'";
            end = "${lib.getExe pkgs.libnotify}/bin/notify-send 'GameMode ended'";
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
  };
}
