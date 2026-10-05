{
  inputs,
  self,
  config,
  ...
}: let
  inherit (config.nixos) modules;
in {
  flake.deploy.nodes.artemis = {
    # Deploys ride the NetBird mesh (no public DNS); when it's down: deploy .#artemis --hostname <LAN IP or 10.100.0.2 via the backup tunnel>.
    hostname = "artemis.jeiang.vpn";
    sshUser = "aidanp";
    sudo = "doas -u";
    profiles.system = {
      user = "root";
      path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.artemis;
    };
  };

  nixos.configurations.artemis.module = {
    imports = [modules.base modules.artemis];
  };

  nixos.modules.artemis = {
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
        # Persistent=true timers' last-trigger stamps, for catch-up after a reboot.
        "/var/lib/systemd/timers"
        "/var/lib/hermes"
        "/var/cache/bonsai-models"
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
        ".renpy"
        ".local/share/Trash"
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".claude";
          mode = "0700";
        }
        ".local/share/fish"
        ".local/share/zoxide"
        ".config/fish"
      ];
      data.files = [".claude.json"];
      cache.directories = [
        ".cache/claude-cli-nodejs"
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
        # Raphael iGPU's PSP rejects SETUP_TMR (0x80000306) on some boots, killing the amdgpu probe and deadlocking udev; stubbing the display function (19:00.0 only) removes the trigger.
        "pci-stub.ids=1002:164e"
        # A hung task does not stop PID 1 from feeding the watchdog; panic so the box reboots and spends its boot try.
        "panic=10"
        "hung_task_panic=1"
        # Initrd emergency mode panics instead of waiting at sulogin.
        "boot.panic_on_fail"
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
    environment.variables = {
      AMD_VULKAN_ICD = "RADV";
      MESA_SHADER_CACHE_MAX_SIZE = "12G";
      # Pin aquamarine to the dGPU: left alone it makes the iGPU primary and renders the whole session there. /dev/dri/egpu is the by-PCI-address symlink from ./hardware.nix; card* numbering is not boot-stable.
      AQ_DRM_DEVICES = "/dev/dri/egpu";
    };
    networking = {
      hostName = "artemis";
      networkmanager.enable = true;
      # No modem hardware; NetworkManager's default pulls this in anyway.
      modemmanager.enable = false;
      # facter marks the detected NICs useDHCP, which also enables dhcpcd; NetworkManager already handles DHCP for them.
      dhcpcd.enable = false;
      nftables.enable = true;
      # nixpkgs#415213: applying the WoL policy is flaky -- verify with `ethtool enp16s0 | grep Wake-on` after deploys.
      interfaces.enp16s0.wakeOnLan.enable = true;
    };
    # facter detects the board's Bluetooth controller and defaults this on; nothing pairs to it.
    hardware.bluetooth.enable = false;
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

    # gopass autosync push key; the public half must be registered as a write-access deploy key on github.com:jeiang/pass.
    sops.secrets."gopass/github-ssh-key" = {
      sopsFile = ./secrets.yaml;
      owner = config.preferences.user.name;
      path = "${config.users.users.${config.preferences.user.name}.home}/.ssh/id_ed25519";
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
          # The restic pattern matches timers too; the backup-freshness alert reads their last trigger.
          "--collector.systemd.unit-include=(netbird|netbird-login|greetd|wireguard-wg-backup|beesd@.*|sshd|qbittorrent|darkhttpd)\\.service|(restic-backups|restic-maintenance)-.*\\.(service|timer)"
        ];
      };

      # The HomeKit Wake-on-LAN Switch resolves artemis.local over mDNS before pinging it.
      avahi.enable = true;

      # No screen reader on a headless box; the graphical-desktop default pulls this in.
      speechd.enable = false;

      hypr-rdp = {
        enable = true;
        sopsFile = ./secrets.yaml;
        settings = {
          bind = "0.0.0.0:3389";
          # No `output`: hypr-rdp manages its own headless output.
          # `auto` would quietly fall back to software H.264 if the VA-API driver ever failed to load.
          h264_backend = "vaapi";
        };
      };
    };

    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "25.05";
  };
}
