{
  # suppress error: evaluation warning: mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash.
  boot.swraid.mdadmConf = ''
    MAILADDR=nobody@nowhere
  '';
  disko.devices = {
    disk = {
      one = {
        type = "disk";
        device = "/dev/nvme0";
        content = {
          type = "gpt";
          partitions = {
            BOOT = {
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            ESP = {
              size = "500M";
              type = "EF00";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            mdadm = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "raid0";
              };
            };
          };
        };
      };
    };
    mdadm = {
      boot = {
        type = "mdadm";
        level = 1;
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          mountOptions = ["umask=0077"];
        };
      };
      raid0 = {
        type = "mdadm";
        level = 0;
        content = {
          type = "gpt";
          partitions.primary = {
            size = "100%";
            content = let
              mountOptions = ["compress-zstd" "noatime"];
            in {
              type = "btrfs";
              extraArgs = ["-f"]; # Override existing partition
              subvolumes = {
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
}
