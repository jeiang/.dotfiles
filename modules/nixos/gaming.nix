{self, ...}: {
  flake.nixosModules.gaming = {
    pkgs,
    lib,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      boxflat
      self.packages.${pkgs.stdenv.hostPlatform.system}.mangohud
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
      (heroic.override {
        extraPkgs = pkgs':
          with pkgs'; [
            gamescope
            gamemode
          ];
      })
    ];
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
        remotePlay.openFirewall = true;
        gamescopeSession.enable = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
      };
    };
    # ~/.steam is intentionally not managed here: Steam's own launcher
    # (steam.sh) expects it to be a real directory containing its own
    # internal symlinks (.steam/steam, .steam/root, .steam/bin32, ... into
    # ~/.local/share/Steam), and recreates that structure itself on every
    # launch if missing — cheap, no real data. Only ~/.local/share/Steam
    # (the actual library) is persisted; see persistence.data.directories
    # on artemis. Do not turn ~/.steam itself into a symlink to
    # ~/.local/share/Steam — that breaks steam.sh (tried, produced
    # "couldn't set up steam data" errors).
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

  flake.nixosModules.vr = {pkgs, ...}: {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "vrstart" ''
        #!/usr/bin/env bash
        export PRESSURE_VESSEL_FILESYSTEMS_RW="$XDG_RUNTIME_DIR/wivrn/comp_ipc"
        exec "$@"
      '')
    ];

    persistence.cache.directories = [
      ".config/wivrn"
    ];

    services.wivrn = {
      enable = true;
      openFirewall = true;
      # steam.importOXRRuntimes = true;
      highPriority = true;
      autoStart = true;
    };

    # hjem.users.${user} = {
    #   files.".config/openxr/1/active_runtime.json".source = "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json";

    #   files.".config/openvr/openvrpaths.vrpath".text = let
    #     steam = "/home/${user}/.local/share/Steam";
    #   in
    #     builtins.toJSON {
    #       version = 1;
    #       jsonid = "vrpathreg";

    #       external_drivers = null;
    #       config = ["${steam}/config"];

    #       log = ["${steam}/logs"];

    #       runtime = [
    #         "${pkgs.xrizer}/lib/xrizer"
    #       ];
    #     };
    # };
  };
}
