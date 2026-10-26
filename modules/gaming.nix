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
            custom = lib.mkIf (config.gaming.pauseUnits != []) (let
              units = lib.escapeShellArgs config.gaming.pauseUnits;
            in {
              start = "systemctl --no-ask-password stop ${units}";
              end = "systemctl --no-ask-password start ${units}";
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
      # gamemoded runs the custom scripts as the operator with no terminal, so polkit grants exactly these start/stop calls.
      security.polkit.extraConfig = lib.mkIf (config.gaming.pauseUnits != []) ''
        polkit.addRule(function(action, subject) {
          var units = ${builtins.toJSON config.gaming.pauseUnits};
          var verb = action.lookup("verb");
          if (action.id == "org.freedesktop.systemd1.manage-units"
              && subject.user == "${config.preferences.user.name}"
              && units.indexOf(action.lookup("unit")) >= 0
              && (verb == "start" || verb == "stop")) {
            return polkit.Result.YES;
          }
        });
      '';
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
