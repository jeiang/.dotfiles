{
  flake.nixosModules.base = {lib, ...}: {
    options.persistence = {
      enable = lib.mkEnableOption "enable persistence";

      nukeRoot = {
        enable = lib.mkEnableOption "roll the btrfs root subvolume back to an empty subvolume on every boot";

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
          type = lib.types.int;
          default = 30;
          description = ''
            Age in days after which old roots under `/old_roots` on the
            rollback device are deleted.
          '';
        };
      };

      volumeGroup = lib.mkOption {
        default = "btrfs_vg";
        description = ''
          Btrfs volume group name
        '';
      };

      user = lib.mkOption {
        default = "username";
        description = ''
          Main user
        '';
      };

      directories = lib.mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      files = lib.mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };

      data.directories = lib.mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      data.files = lib.mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };

      cache.directories = lib.mkOption {
        default = [];
        description = ''
          directories to persist
        '';
      };

      cache.files = lib.mkOption {
        default = [];
        description = ''
          files to persist
        '';
      };
    };
  };
}
