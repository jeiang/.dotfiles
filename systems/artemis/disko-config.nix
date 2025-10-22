let
  btrfsMountOptions = [
    "rw"
    "ssd_spread"
    "commit=150"
    "compress=zstd"
    "noatime"
    "discard=async"
  ];
  btrfsRootMount = "/mnt/root";
in {
  boot.loader.efi.canTouchEfiVariables = true;
  # not managed by disko
  fileSystems = {
    "/mnt/Mumei" = {
      device = "/dev/disk/by-label/Mumei";
      neededForBoot = false;
      fsType = "ntfs-3g";
      options = ["rw" "uid=1000"];
    };
    "${btrfsRootMount}" = {
      device = "/dev/disk/by-partlabel/disk-nvme2-root";
      neededForBoot = false;
      fsType = "btrfs";
      options = btrfsMountOptions;
    };
  };
  services.beesd.filesystems = {
    "-" = {
      spec = btrfsRootMount;
      hashTableSizeMB = 24576;
      extraOptions = ["--thread-min" "1" "--loadavg-target" "5.0" "--scan-mode" "4"];
      verbosity = "err";
    };
  };
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "1024M";
              name = "boot";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "umask=0022"
                  "iocharset=utf8"
                  "rw"
                ];
              };
            };
            empty = {
              size = "100%";
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            empty = {
              size = "100%";
            };
          };
        };
      };
      nvme2 = {
        type = "disk";
        device = "/dev/nvme2n1";
        content = {
          type = "gpt";
          partitions = {
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-m raid0"
                  "-d raid0"
                  "/dev/nvme0n1p2"
                  "/dev/nvme1n1p1"
                  "/dev/nvme2n1p1"
                ];
                subvolumes = {
                  "/rootfs" = {
                    mountOptions = btrfsMountOptions;
                    mountpoint = "/";
                  };
                  "/log" = {
                    mountOptions = btrfsMountOptions;
                    mountpoint = "/var/log";
                  };
                  "/home" = {
                    mountOptions = btrfsMountOptions;
                    mountpoint = "/home";
                  };
                  "/home/aidanp" = {};
                  "/nix" = {
                    mountOptions = btrfsMountOptions;
                    mountpoint = "/nix";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
