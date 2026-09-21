{self, ...}: {
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.gaming.pauseUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Units stopped while a game runs and started again when it ends.
      '';
    };

    config = {
      users.users.${config.preferences.user.name}.extraGroups = ["gamemode"];

      environment.systemPackages = with pkgs; [
        self.packages.${pkgs.stdenv.hostPlatform.system}.mangohud
        (prismlauncher.override {
          # ffmpeg required by some mod
          additionalPrograms = [ffmpeg];

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
      programs = {
        gamescope.enable = true;
        gamemode = {
          enable = true;
          settings = {
            general.renice = 10;
            # Warning: GPU optimisations have the potential to damage hardware
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              # The iGPU's display function is pci-stubbed, so the dGPU is card1, not card0.
              gpu_device = 1;
              amd_performance_level = "high";
            };
            # gamemoded runs this as the operator, so it rides wheel's
            # passwordless doas (modules/doas.nix) rather than needing a doas
            # rule of its own.
            custom = lib.mkIf (config.gaming.pauseUnits != []) (let
              units = lib.escapeShellArgs config.gaming.pauseUnits;
            in {
              start = "doas systemctl stop ${units}";
              end = "doas systemctl start ${units}";
            });
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

      persistence = {
        data.directories = [
          ".local/share/Steam"
          ".config/heroic"
          ".config/PrismLauncher"
          ".local/share/heroic"
          ".local/share/PrismLauncher"
          ".local/share/rivalsmodmanager"
        ];
        cache.directories = [
          ".cache/heroic"
          ".cache/PrismLauncher"
          ".cache/protontricks"
        ];
      };
    };
  };
}
