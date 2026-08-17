{self, ...}: {
  flake.nixosModules.gaming = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
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
        };
      };
      steam = {
        enable = true;
        extest.enable = true;
        protontricks.enable = true;
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
}
