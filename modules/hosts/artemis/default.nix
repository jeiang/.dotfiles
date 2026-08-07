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
      # zen4 CPU with the BORE scheduler and full LTO.
      originalKernel = inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linux-cachyos-latest;
      kernel = originalKernel.override {
        pname = "linux-cachyos-bore-lto-zen4";
        processorOpt = "zen4";
        cpusched = "bore";
        lto = "full";
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
        self.nixosModules.llama-swap

        # disks
        self.diskoConfigurations.artemis
      ];

      persistence = {
        enable = true;
        # Roll the "/rootfs" btrfs subvolume (mounted as /, see
        # ./disko.nix) back to empty on every boot, in the initrd, before
        # anything else is mounted. Only paths explicitly listed below
        # survive a reboot; everything else on / is gone. device matches
        # the same partition disko.nix mounts for /persist, /nix, etc. —
        # any one member device of the multi-device btrfs filesystem works.
        nukeRoot = {
          enable = true;
          device = "/dev/disk/by-partlabel/disk-nvme3-root";
          subvolume = "rootfs";
        };

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
          # GGUF weights fetched by llama-swap-models
          # (modules/nixos/llama-swap.nix). Not derivable state: without this
          # entry nukeRoot drops tens of GB of models on every boot and the
          # unit re-downloads all of them before llama-swap can start.
          "/var/lib/llama-swap-models"
        ];

        # User-level state.
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
          ".renpy"
          ".local/share/Trash"
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
          {
            # Claude Code's whole per-user state tree: settings.json,
            # memory/, skills/, plugins/, per-project session history and
            # todos — and .credentials.json, the OAuth tokens it writes
            # here on Linux (no system keychain), hence 0700 like .ssh.
            directory = ".claude";
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
          ".config/obsidian"
          ".config/PrismLauncher"
          ".config/qBittorrent"
          ".config/easyeffects"
          ".local/share/heroic"
          ".local/share/PrismLauncher"
          ".local/share/qBittorrent"
          ".local/share/rivalsmodmanager"
        ];
        # ~/.claude.json is Claude Code's global config file (onboarding
        # state, per-project trust/history, MCP server entries) and sits
        # next to ~/.claude rather than inside it. impermanence creates an
        # empty file at this path if /persist has none yet; Claude Code
        # treats an unparseable config as a fresh one (it moves it aside to
        # ~/.claude.json.corrupted) rather than failing to start.
        data.files = [".claude.json"];
        cache.directories = [
          # Per-project MCP server logs; regenerated, safe to lose.
          ".cache/claude-cli-nodejs"
          ".cache/devenv"
          ".cache/direnv"
          ".cache/nix-direnv"
          ".cache/danksearch"
          ".cache/heroic"
          ".cache/PrismLauncher"
          ".cache/protontricks"
          ".local/state/DankMaterialShell"
          ".local/state/nix"
          ".local/state/wivrn"
          ".local/state/xrizer"
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
        blacklistedKernelModules = ["algif_aead"];
      };
      # Claude Code, here rather than in the shared toolbox
      # (modules/nixos/toolbox.nix) — it's a workstation tool, not
      # something the legion nodes need. The nixpkgs derivation already
      # pins the CLI's own updater off (DISABLE_AUTOUPDATER), so it stays
      # on whatever version this flake's nixpkgs input carries. Its state
      # lives in ~/.claude and ~/.claude.json, both persisted above.
      environment.systemPackages = [pkgs.claude-code];
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
    };
  };
}
