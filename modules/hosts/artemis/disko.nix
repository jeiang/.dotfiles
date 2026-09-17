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
    # by-id survives NVMe kernel-name churn across boots; serials are from facter.json.
    nvmeById = serial: "/dev/disk/by-id/nvme-SHPP41-2000GM_${serial}";
    nvme0Serial = "ASCBN54621070BS4Z";
    nvme1Serial = "ASC7N440910607A5K";
    nvme3Serial = "ASC7N440910607A6A";
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
        # This drive isn't always attached; don't let a missing HDD drop an unattended boot to emergency mode.
        options = ["rw" "uid=1000" "nofail" "x-systemd.device-timeout=10s"];
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
          device = nvmeById nvme0Serial;
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
                    "umask=0077"
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
          device = nvmeById nvme1Serial;
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
          device = nvmeById nvme3Serial;
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
                    "${nvmeById nvme0Serial}-part2"
                    "${nvmeById nvme1Serial}-part1"
                    "${nvmeById nvme3Serial}-part1"
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
