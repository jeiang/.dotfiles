{
  inputs,
  lib,
  ...
}: {
  flake.diskoConfigurations.artemis = let
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
    imports = [
      inputs.disko.nixosModules.disko
    ];

    boot.loader.efi.canTouchEfiVariables = true;
    # not managed by disko
    fileSystems = {
      "/mnt/Mumei" = {
        device = "/dev/disk/by-label/Mumei";
        neededForBoot = false;
        fsType = "ntfs-3g";
        options = ["rw" "uid=1000"];
      };
      # for bees
      "${btrfsRootMount}" = {
        device = "/dev/disk/by-partlabel/disk-nvme3-root";
        neededForBoot = false;
        fsType = "btrfs";
        options = btrfsMountOptions;
      };
    };
    services.beesd.filesystems = {
      "-" = {
        spec = btrfsRootMount;
        hashTableSizeMB = 4096;
        extraOptions = ["--scan-mode" "4"];
        verbosity = "err";
      };
    };
    # bees holds btrfs extent locks that stall game I/O, so it runs in a nightly window; missed windows are skipped, never run late.
    systemd = {
      services."beesd@-".wantedBy = lib.mkForce [];
      timers.beesd-start = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "03:00";
          Unit = "beesd@-.service";
        };
      };
      services.beesd-stop = {
        script = "systemctl stop 'beesd@-.service'";
        serviceConfig.Type = "oneshot";
      };
      timers.beesd-stop = {
        wantedBy = ["timers.target"];
        timerConfig.OnCalendar = "09:00";
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
                size = "1800G";
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
                size = "1800G";
              };
            };
          };
        };
        nvme3 = {
          type = "disk";
          device = "/dev/nvme3n1";
          content = {
            type = "gpt";
            partitions = {
              root = {
                size = "1800G";
                content = {
                  type = "btrfs";
                  # Intentional raid0 across all 3 nvme drives for throughput; data loss on any single drive failure is accepted.
                  extraArgs = [
                    "-f"
                    "-m raid0"
                    "-d raid0"
                    "/dev/nvme0n1p2"
                    "/dev/nvme1n1p1"
                    "/dev/nvme3n1p1"
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
                    # /home is intentionally not its own subvolume: only listed persistence.data/cache paths survive.
                    "/nix" = {
                      mountOptions = btrfsMountOptions;
                      mountpoint = "/nix";
                    };
                    "/persist" = {
                      mountOptions = btrfsMountOptions;
                      mountpoint = "/persist";
                    };
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
