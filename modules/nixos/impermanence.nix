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
    # anything older than nukeRoot.maxAge days, recursing into nested
    # subvolumes first since btrfs refuses to delete a non-empty one), then
    # recreates it empty. Only ever touches the "${cfg.nukeRoot.subvolume}"
    # top-level subvolume mounted at "/" — /persist, /nix, /log, and any
    # leftover top-level /home are separate sibling subvolumes on the same
    # filesystem and are never listed or descended into here.
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

        # impermanence only bind-mounts the paths listed below; it does not
        # migrate any data that already exists at those paths. Before
        # rebooting (or running an activation that would otherwise lose
        # unpersisted state) after adding or changing an entry here, copy the
        # current contents into its target under /persist, e.g.:
        #   cp -a /etc/machine-id /persist/etc/machine-id
        #   cp -a /home/${user}/Projects /persist/data/home/${user}/Projects
        # On artemis, `just migrate-persist` (modules/hosts/artemis/migrate-persist.sh)
        # does this for every path in the current persistence.* config — run
        # it on artemis itself before rebooting. Never assume this module
        # migrates existing state for you.
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

      # systemd stage 1 (the default since this flake tracks nixos-unstable):
      # roll back before the root filesystem is mounted at all. Ordering
      # matches the nix-community/impermanence PR #321 reference: run once
      # the root block device shows up and hibernation resume had its
      # chance to run first, and finish before sysroot.mount so the fresh
      # empty subvolume is what actually gets mounted as /.
      (lib.mkIf (cfg.enable && cfg.nukeRoot.enable && config.boot.initrd.systemd.enable) {
        boot.initrd.systemd = {
          # findutils for `find` in rollbackScript below — btrfs-progs is
          # already pulled in automatically since / is btrfs, but findutils
          # isn't part of the default systemd-initrd tool set.
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
              # Let hibernation resume run (and consume the pre-rollback
              # root) before this alters any data.
              "local-fs-pre.target"
            ];
            script = rollbackScript;
          };
        };
      })

      # Classic (non-systemd) initrd fallback, only relevant if systemd
      # stage 1 is ever explicitly turned off for this host. postResumeCommands
      # runs after the kernel's own hibernation-resume attempt, matching the
      # "resume before rollback" ordering used in the systemd-stage-1 path
      # above.
      (lib.mkIf (cfg.enable && cfg.nukeRoot.enable && !config.boot.initrd.systemd.enable) {
        boot.initrd.postResumeCommands = lib.mkAfter rollbackScript;
      })
    ];
  };
}
