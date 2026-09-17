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
    deploy.nodes.artemis = {
      # Deploys ride the NetBird mesh (no public DNS); when it's down: deploy .#artemis --hostname <LAN IP or 10.100.0.2 via the backup tunnel>.
      hostname = "artemis.jeiang.vpn";
      sshUser = "aidanp";
      sudo = "doas -u";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.artemis;
      };
    };

    nixosModules.artemisConfiguration = {
      config,
      pkgs,
      ...
    }: let
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
        self.nixosModules.artemisBootHealth
        self.nixosModules.desktop
        self.nixosModules.netbird
        self.nixosModules.speedtest
        self.nixosModules.tcp-tuning
        self.nixosModules.gaming
        self.nixosModules.sunshine
        self.nixosModules.backupTunnel
        self.nixosModules.impermanence
        self.nixosModules.hypr-rdp
        self.nixosModules.toolboxArtemis
        self.nixosModules.nixArtemisExtras

        self.diskoConfigurations.artemis
      ];

      persistence = {
        enable = true;
        nukeRoot = {
          enable = true;
          device = "/dev/disk/by-partlabel/disk-nvme3-root";
          subvolume = "rootfs";
        };

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
          # Persistent=true timers' last-trigger stamps, for catch-up after a reboot.
          "/var/lib/systemd/timers"
        ];

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
            directory = ".claude";
            mode = "0700";
          }
          ".local/share/fish"
          ".local/share/direnv"
          ".local/share/devenv"
          ".local/share/zoxide"
          ".config/fish"
          ".config/gopass"
          {
            directory = ".config/hypr-rdp";
            mode = "0700";
          }
          ".config/heroic"
          ".config/PrismLauncher"
          ".local/share/heroic"
          ".local/share/PrismLauncher"
          ".local/share/rivalsmodmanager"
        ];
        data.files = [".claude.json"];
        cache.directories = [
          ".cache/claude-cli-nodejs"
          ".cache/devenv"
          ".cache/direnv"
          ".cache/nix-direnv"
          ".cache/heroic"
          ".cache/PrismLauncher"
          ".cache/protontricks"
          # Mesa's default (multi-file, no MESA_DISK_CACHE_DATABASE) shader cache dir.
          ".cache/mesa_shader_cache"
          ".local/state/nix"
        ];
      };

      boot = {
        loader.systemd-boot = {
          enable = true;
          consoleMode = "max";
          bootCounting = {
            enable = true;
            tries = 2;
          };
        };
        supportedFilesystems = ["ntfs"];
        kernelParams = [
          # This host streams unattended: let amdgpu attempt an engine reset instead of leaving the GPU wedged until reboot.
          "amdgpu.gpu_recovery=1"
          # Raphael iGPU's PSP rejects SETUP_TMR (0x80000306) on ~25% of boots, killing the amdgpu probe and (on 7.1.6) deadlocking udev; stubbing the display function (19:00.0 only) removes the trigger.
          "pci-stub.ids=1002:164e"
          # A wedged amdgpu (or any other hung task) doesn't stop PID 1 petting the watchdog, so panic on a hang and let the panic (and the armed hardware watchdog) reboot the box.
          "panic=10"
          "hung_task_panic=1"
        ];
        # facter also loads amdgpu in the initrd; ship pci-stub there too so it can win the race (the softdep below orders modprobe everywhere else).
        initrd.kernelModules = ["pci-stub" "sp5100_tco"];
        # amdgpu reaches the initrd via two paths and only one respects list order; the softdep makes every modprobe pull pci-stub first.
        extraModprobeConfig = "softdep amdgpu pre: pci-stub";
        initrd.systemd.settings.Manager.RuntimeWatchdogSec = "30s";
        kernelPackages = let
          helpers = pkgs.callPackage "${inputs.nix-cachyos-kernel.outPath}/helpers.nix" {};
        in
          helpers.kernelModuleLLVMOverride (pkgs.linuxKernel.packagesFor kernel);
        blacklistedKernelModules = ["algif_aead"];
      };
      environment.systemPackages = [pkgs.claude-code];

      environment.variables = {
        AMD_VULKAN_ICD = "RADV";
        MESA_SHADER_CACHE_MAX_SIZE = "12G";
        # Pin aquamarine to the dGPU: left alone it makes the iGPU primary and renders the whole session there. /dev/dri/egpu is the by-PCI-address symlink from ./hardware.nix; card* numbering is not boot-stable.
        AQ_DRM_DEVICES = "/dev/dri/egpu";
      };
      networking = {
        hostName = "artemis";
        networkmanager.enable = true;
        # facter marks the detected NICs useDHCP, which also enables dhcpcd; NetworkManager already handles DHCP for them.
        dhcpcd.enable = false;
        nftables.enable = true;
        # nixpkgs#415213: applying the WoL policy is flaky -- verify with `ethtool enp16s0 | grep Wake-on` after deploys.
        interfaces.enp16s0.wakeOnLan.enable = true;
      };
      users.users.${config.preferences.user.name}.extraGroups = ["networkmanager"];

      nix.settings.trusted-users = ["@wheel"];

      # BIOS must also be set to "Restore AC Power Loss: Power On" -- firmware setting, not expressible here.
      systemd.settings.Manager = {
        RuntimeWatchdogSec = "30s";
        RebootWatchdogSec = "10min";
      };
      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      sops.secrets."netbird/setup-key".sopsFile = ./secrets.yaml;
      services.netbird.clients.default.login = {
        enable = true;
        setupKeyFile = config.sops.secrets."netbird/setup-key".path;
      };

      # gopass autosync push key; the public half must be registered as a write-access deploy key on github.com:jeiang/pass.
      sops.secrets."gopass/github-ssh-key" = {
        sopsFile = ./secrets.yaml;
        owner = "aidanp";
        path = "/home/aidanp/.ssh/id_ed25519";
        mode = "0600";
      };
      # Pinned so the first unattended push never stalls on an interactive known-hosts prompt.
      programs.ssh.knownHosts."github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

      # Grouped in one attrset: statix W20 fires on a third top-level `services.*` key.
      services = {
        prometheus.exporters.node = {
          enable = true;
          enabledCollectors = ["systemd"];
          extraFlags = [
            "--collector.systemd.unit-include=(netbird|netbird-login|greetd|wireguard-wg-backup|beesd@.*|sshd)\\.service"
          ];
        };

        # The HomeKit Wake-on-LAN Switch resolves artemis.local over mDNS before pinging it.
        avahi.enable = true;

        hypr-rdp = {
          enable = true;
          user = "aidanp";
          username = "aidanp";
          sopsFile = ./secrets.yaml;
          settings = {
            bind = "0.0.0.0:3389";
            # No `output` on purpose: a pinned DP-1 fails startup once the powered-down display's EDID vanishes; hypr-rdp manages its own headless output.
            # `auto` would quietly fall back to software H.264 if the VA-API driver ever failed to load.
            h264_backend = "vaapi";
          };
        };
      };

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };
  };
}
