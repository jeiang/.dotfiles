{
  flake.nixosModules.base = {
    config,
    lib,
    ...
  }: let
    cfg = config.persistence;
    persistenceEntryType = lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything);
    persistenceListOption = description:
      lib.mkOption {
        type = lib.types.listOf persistenceEntryType;
        default = [];
        description = "${description} Entries may be strings or impermanence-compatible attribute sets.";
      };
  in {
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

    config.assertions = [
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
  };
}
