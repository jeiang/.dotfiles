{inputs, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    pkgs,
    utils,
    ...
  }: let
    cfg = config.persistence;
    user = config.preferences.user.name;

    rootDeviceUnit = "${utils.escapeSystemdPath cfg.nukeRoot.device}.device";

    # Moves the current root subvolume aside under /old_roots (pruning
    # entries older than maxAge) and recreates it empty; sibling subvolumes
    # (/persist, /nix, /log) are never touched.
    rollbackScript = ''
      mkdir /btrfs_tmp
      mount -o subvolid=5 ${cfg.nukeRoot.device} /btrfs_tmp
      if [[ -e /btrfs_tmp/${cfg.nukeRoot.subvolume} ]]; then
          mkdir -p /btrfs_tmp/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/${cfg.nukeRoot.subvolume})" "+%Y-%m-%-d_%H:%M:%S")
          mv "/btrfs_tmp/${cfg.nukeRoot.subvolume}" "/btrfs_tmp/old_roots/$timestamp"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +${toString cfg.nukeRoot.maxAge}); do
          delete_subvolume_recursively "$i"
      done

      btrfs subvolume create "/btrfs_tmp/${cfg.nukeRoot.subvolume}"
      umount /btrfs_tmp
    '';
  in {
    imports = [
      inputs.impermanence.nixosModules.impermanence
    ];

    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        fileSystems."/persist".neededForBoot = true;

        # impermanence only bind-mounts; it never migrates existing data. Run
        # `just migrate-persist` on artemis before rebooting after changes.
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
          # findutils: `find` is not in the default systemd-initrd tool set
          initrdBin = [pkgs.btrfs-progs pkgs.findutils];
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
