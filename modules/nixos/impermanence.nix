{inputs, ...}: {
  nixos.modules.impermanence = {
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

    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        fileSystems."/persist".neededForBoot = true;

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
