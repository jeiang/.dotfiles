{
  boot.loader.efi.canTouchEfiVariables = true;
  # not managed by disko
  fileSystems."/mnt/Mumei" = {
    device = "/dev/disk/by-label/Mumei";
    neededForBoot = false;
    fsType = "ntfs-3g";
    options = ["rw" "uid=1000"];
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
                subvolumes = let
                  mountOptions = [
                    "rw"
                    "ssd_spread"
                    "commit=150"
                    "compress=zstd"
                    "noatime"
                    "discard=async"
                  ];
                in {
                  "/rootfs" = {
                    inherit mountOptions;
                    mountpoint = "/";
                  };
                  "/log" = {
                    inherit mountOptions;
                    mountpoint = "/var/log";
                  };
                  "/home" = {
                    inherit mountOptions;
                    mountpoint = "/home";
                  };
                  "/home/aidanp" = {};
                  "/nix" = {
                    inherit mountOptions;
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
