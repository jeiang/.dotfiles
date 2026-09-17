{inputs, ...}: {
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    utils,
    ...
  }: let
    cfg = config.persistence;
    user = config.preferences.user.name;
    persistenceEntryType = lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything);
    persistenceListOption = description:
      lib.mkOption {
        type = lib.types.listOf persistenceEntryType;
        default = [];
        description = "${description} Entries may be strings or impermanence-compatible attribute sets.";
      };

    rootDeviceUnit = "${utils.escapeSystemdPath cfg.nukeRoot.device}.device";

    # Moves the current root subvolume aside under /old_roots (pruning
    # entries older than maxAge) and recreates it empty; sibling subvolumes
    # (/persist, /nix, /log) are never touched.
    rollbackScript = ''
      mkdir /btrfs_tmp
      mount -o subvolid=5 ${cfg.nukeRoot.device} /btrfs_tmp
      mkdir -p /btrfs_tmp/old_roots

      this_boot=$(date +%Y-%m-%dT%H%M%S)
      if [[ -e /btrfs_tmp/${cfg.nukeRoot.subvolume} ]]; then
          mv "/btrfs_tmp/${cfg.nukeRoot.subvolume}" "/btrfs_tmp/old_roots/$this_boot"
      fi

      # Create root before pruning, so a failed prune never leaves no root to mount.
      if [[ ! -e /btrfs_tmp/${cfg.nukeRoot.subvolume} ]]; then
          btrfs subvolume create "/btrfs_tmp/${cfg.nukeRoot.subvolume}"
      fi

      delete_subvolume_recursively() {
          local IFS=$'\n' i
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      # Age by name: a moved subvolume keeps the previous boot's mtime.
      cutoff=$(date --date="-${toString cfg.nukeRoot.maxAge} days" +%Y-%m-%dT%H%M%S)
      for i in /btrfs_tmp/old_roots/*; do
          [[ -e "$i" ]] || continue
          name=$(basename "$i")
          [[ "$name" == "$this_boot" ]] && continue
          if [[ "$name" < "$cutoff" ]]; then
              # best-effort: a failed delete must never block boot
              delete_subvolume_recursively "$i" || echo "rollback-root: failed to prune $i" >&2
          fi
      done

      umount /btrfs_tmp
    '';
  in {
    imports = [
      inputs.impermanence.nixosModules.impermanence
    ];

    options.persistence = {
      enable = lib.mkEnableOption "persistent storage mounts";

      nukeRoot = {
        enable = lib.mkEnableOption "rolling the btrfs root subvolume back to an empty subvolume on every boot";

        device = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "/dev/disk/by-partlabel/disk-nvme3-root";
          description = ''
            Block device (or `/dev/disk/by-*` path) belonging to the btrfs
            filesystem whose top-level subvolume (`subvolid=5`) is mounted
            in the initrd to perform the rollback. For a multi-device btrfs
            filesystem, any one of its member devices works.
          '';
        };

        subvolume = lib.mkOption {
          type = lib.types.str;
          default = "rootfs";
          description = ''
            Name of the top-level btrfs subvolume that is mounted as `/`
            and gets moved aside and recreated empty on every boot.
          '';
        };

        maxAge = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 30;
          description = ''
            Age in days after which old roots under `/old_roots` on the
            rollback device are deleted.
          '';
        };
      };

      directories = persistenceListOption "System directories to persist under `/persist`.";
      files = persistenceListOption "System files to persist under `/persist`.";

      data.directories = persistenceListOption "User data directories to persist under `/persist/data`.";
      data.files = persistenceListOption "User data files to persist under `/persist/data`.";

      cache.directories = persistenceListOption "User cache directories to persist under `/persist/cache`.";
      cache.files = persistenceListOption "User cache files to persist under `/persist/cache`.";
    };

    config = lib.mkMerge [
      {
        assertions = [
          {
            assertion = !cfg.nukeRoot.enable || cfg.enable;
            message = "persistence.nukeRoot.enable requires persistence.enable";
          }
          {
            assertion = !cfg.nukeRoot.enable || cfg.nukeRoot.device != "";
            message = "persistence.nukeRoot.device must be set when root rollback is enabled";
          }
          {
            assertion = !cfg.nukeRoot.enable || cfg.nukeRoot.subvolume != "";
            message = "persistence.nukeRoot.subvolume must be set when root rollback is enabled";
          }
        ];
      }

      (lib.mkIf cfg.enable {
        fileSystems."/persist".neededForBoot = true;

        sops.age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

        # impermanence never migrates existing data: run `just migrate-persist`
        # on artemis before deploying a persistence.* change.
        environment.persistence = {
          "/persist" = {
            inherit (cfg) directories files;
          };

          "/persist/data".users.${user} = {
            directories = cfg.data.directories;
            files = cfg.data.files;
          };

          "/persist/cache".users.${user} = {
            directories = cfg.cache.directories;
            files = cfg.cache.files;
          };
        };
      })

      (lib.mkIf (cfg.enable && cfg.nukeRoot.enable && config.boot.initrd.systemd.enable) {
        boot.initrd.systemd = {
          initrdBin = [pkgs.btrfs-progs];
          services.rollback-root = {
            description = "Roll back btrfs root subvolume to an empty subvolume";
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
            requiredBy = ["initrd.target"];
            before = ["sysroot.mount"];
            requires = [rootDeviceUnit];
            after = [
              rootDeviceUnit
              # let hibernation resume consume the pre-rollback root first
              "local-fs-pre.target"
            ];
            script = rollbackScript;
          };
        };
      })

      # postResumeCommands keeps the resume-before-rollback ordering in the
      # classic initrd.
      (lib.mkIf (cfg.enable && cfg.nukeRoot.enable && !config.boot.initrd.systemd.enable) {
        boot.initrd.postResumeCommands = lib.mkAfter rollbackScript;
      })
    ];
  };
}
