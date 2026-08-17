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
      # NetBird mesh DNS name; deploys ride the mesh (artemis has no
      # public DNS). When the mesh is down, `deploy .#artemis --hostname
      # <LAN IP or 10.100.0.2 via the backup tunnel>` overrides it.
      hostname = "artemis.jeiang.vpn";
      # No dedicated deploy user (unlike legion): artemis is a personal
      # box whose admin user already has passwordless doas via wheel
      # (modules/nixos/security.nix); deploy-rs's sudo prefix and its
      # magic-rollback canary rm both run through that.
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
        self.nixosModules.gaming
        self.nixosModules.sunshine
        self.nixosModules.backupTunnel
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
          ".config/heroic"
          ".config/PrismLauncher"
          ".local/share/heroic"
          ".local/share/PrismLauncher"
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
          ".cache/heroic"
          ".cache/PrismLauncher"
          ".cache/protontricks"
          ".local/state/nix"
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
          # Let amdgpu attempt an engine reset instead of leaving the GPU
          # wedged until reboot -- this host streams unattended and a dead
          # GPU is otherwise a truck-roll (docs/research/
          # unattended-nixos-gaming-remote-access.md).
          "amdgpu.gpu_recovery=1"
        ];
        # Unattended hang recovery: a D-state amdgpu wedge doesn't stop
        # PID 1 from petting the hardware watchdog, so panic on hung
        # tasks explicitly and let the panic reboot the box. The watchdog
        # (systemd.settings.Manager below) remains the backstop for the
        # cases where even the panic path is dead.
        kernel.sysctl = {
          "kernel.hung_task_panic" = 1;
          "kernel.panic" = 10;
        };
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
        # So the planned ESP8266 magic-packet sender (and any LAN
        # neighbor) can wake this box after a manual shutdown. Known
        # nixpkgs flakiness applying the policy (nixpkgs#415213) --
        # verify with `ethtool enp16s0 | grep Wake-on` after deploys.
        interfaces.enp16s0.wakeOnLan.enable = true;
      };

      # Hardware watchdog (sp5100_tco on this X670E board): reboot on a
      # hard hang PID 1 can't recover from. BIOS must also be set to
      # "Restore AC Power Loss: Power On" so outages don't strand the
      # box -- firmware setting, not expressible here.
      systemd.settings.Manager = {
        RuntimeWatchdogSec = "30s";
        RebootWatchdogSec = "10min";
      };
      # This host is an always-on streaming/inference server now; nobody
      # is at the keyboard to resume it, AMD suspend/resume is unreliable,
      # and WoL doesn't cross the NetBird mesh.
      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
        hibernate.enable = false;
        hybrid-sleep.enable = false;
      };

      # Setup-key enrollment, same shape as the Legion fleet
      # (modules/hosts/legion/default.nix): inert while the current
      # SSO-registered state in /var/lib/netbird stays valid (the login
      # unit only acts on NeedsLogin), and re-enrolls declaratively if
      # that state is ever lost. The key itself is an operator-filled
      # placeholder until the runbook
      # (docs/runbooks/artemis-always-on-setup.md) is executed.
      sops.secrets."netbird/setup-key".sopsFile = ./secrets.yaml;
      services.netbird.clients.default.login = {
        enable = true;
        setupKeyFile = config.sops.secrets."netbird/setup-key".path;
      };

      # Push key for gopass autosync (github.com:jeiang/pass) -- replaces
      # the Bitwarden SSH agent, which part 3 removes and which needed an
      # unlocked vault (useless unattended). sops-nix links the decrypted
      # key into the persisted ~/.ssh; register the public half as a
      # write-access deploy key per the always-on runbook.
      sops.secrets."gopass/github-ssh-key" = {
        sopsFile = ./secrets.yaml;
        owner = "aidanp";
        path = "/home/aidanp/.ssh/id_ed25519";
        mode = "0600";
      };
      # Pin GitHub's published ed25519 host key so the first unattended
      # push never stalls on an interactive known-hosts prompt.
      programs.ssh.knownHosts."github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

      # Scraped by legion-node3's VictoriaMetrics over the mesh
      # (modules/nixos/monitoring/default.nix job "node"). Same
      # trustedInterfaces-only reachability as the Legion nodes: the
      # netbird interface is trusted, nothing is opened publicly.
      services.prometheus.exporters.node.enable = true;

      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
    };
  };
}
