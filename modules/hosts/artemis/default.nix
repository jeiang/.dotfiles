{
  inputs,
  self,
  ...
}: {
  flake = {
    nixosConfigurations.artemis = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.artemisConfiguration
      ];
    };
    nixosModules.artemisConfiguration = {pkgs, ...}: let
      # Desktop-only performance tuning: CachyOS kernel built for this host's
      # zen4 CPU with the BORE scheduler and full LTO, guided by the AutoFDO
      # profile in ./kernel.afdo. Not portable to other hosts as-is.
      originalKernel = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linux-cachyos-latest;
      kernel = originalKernel.override {
        pname = "linux-cachyos-bore-lto-zen4";
        processorOpt = "zen4";
        cpusched = "bore";
        lto = "full";
        autofdo = ./kernel.afdo;
      };
    in {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.artemisHardware
        self.nixosModules.doas
        self.nixosModules.desktop
        self.nixosModules.netbird
        self.nixosModules.vr
        self.nixosModules.gaming
        self.nixosModules.impermanence

        # disks
        self.diskoConfigurations.artemis
      ];

      persistence = {
        enable = true;
        # /root isn't covered by any persistence entry below, so wipe it on
        # every boot instead of letting it silently accumulate on the
        # (non-ephemeral) root filesystem.
        nukeRoot.enable = true;

        # Core system state that has to survive reinstalls/rebuilds: host
        # identity, generated secrets, and machine-specific network/pairing
        # state. See modules/nixos/impermanence.nix for the reminder that
        # none of this migrates automatically.
        files = [
          "/etc/machine-id"
          "/var/lib/systemd/random-seed"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
          "/etc/ssh/ssh_host_rsa_key"
          "/etc/ssh/ssh_host_rsa_key.pub"
        ];
        directories = [
          "/var/lib/nixos"
          "/etc/NetworkManager/system-connections"
          "/var/lib/NetworkManager"
          "/var/lib/bluetooth"
          "/var/lib/netbird"
        ];

        # User-level state. .mozilla/.cache/mozilla, .local/state/wireplumber,
        # and .config/wivrn are already declared by the firefox, pipewire,
        # and vr modules respectively, so they aren't repeated here.
        data.directories = [
          "Desktop"
          "Documents"
          "Downloads"
          "Pictures"
          "Videos"
          "Music"
          "Projects"
          "Games"
          ".local/share/Steam"
          {
            directory = ".ssh";
            mode = "0700";
          }
          {
            directory = ".gnupg";
            mode = "0700";
          }
          {
            directory = ".password-store";
            mode = "0700";
          }
          {
            directory = ".kube";
            mode = "0700";
          }
          {
            directory = ".local/share/keyrings";
            mode = "0700";
          }
          ".local/share/fish"
          ".local/share/direnv"
          ".local/share/devenv"
          ".local/share/zoxide"
          ".krew"
          ".config/fish"
          ".config/gopass"
          ".config/DankMaterialShell"
          ".config/Bitwarden"
          ".config/discord"
          ".config/heroic"
          ".config/PrismLauncher"
          ".config/qBittorrent"
          ".config/easyeffects"
          ".local/share/heroic"
          ".local/share/PrismLauncher"
          ".local/share/qBittorrent"
        ];
        cache.directories = [
          ".cache/devenv"
          ".cache/direnv"
          ".cache/nix-direnv"
          ".cache/danksearch"
          ".cache/heroic"
          ".cache/PrismLauncher"
          ".cache/protontricks"
        ];
      };

      boot = {
        loader.systemd-boot.enable = true;
        loader.systemd-boot.consoleMode = "max";
        supportedFilesystems = ["ntfs"];
        tmp.cleanOnBoot = true;
        plymouth = {
          enable = true;
          theme = "black_hud";
          themePackages = with pkgs; [
            (adi1090x-plymouth-themes.override {
              selected_themes = ["black_hud"];
            })
          ];
        };
        # Enable "Silent boot"
        consoleLogLevel = 3;
        initrd.verbose = false;
        kernelParams = [
          "quiet"
          "udev.log_level=3"
          "systemd.show_status=auto"
        ];
        kernelPackages = let
          helpers = pkgs.callPackage "${inputs.nix-cachyos-kernel.outPath}/helpers.nix" {};
        in
          helpers.kernelModuleLLVMOverride (pkgs.linuxKernel.packagesFor kernel);
        # extraModulePackages = [config.boot.kernelPackages.zenpower];
        # kernelModules = ["zenpower"];
        blacklistedKernelModules = ["algif_aead"];
      };
      environment.variables = {
        AMD_VULKAN_ICD = "RADV";
        MESA_SHADER_CACHE_MAX_SIZE = "12G";
      };
      networking = {
        hostName = "artemis";
        networkmanager.enable = true;
        nftables.enable = true;
      };
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
      users.users.root.openssh.authorizedKeys.keys = [
        "AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
  };
}
