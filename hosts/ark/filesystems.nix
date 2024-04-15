{
  # for mdadm
  # nix-community/disko#451
  boot.swraid.mdadmConf = ''
    MAILADDR aidan@aidanpinard.co
  '';
  disko.devices = {
    disk = {
      left = {
        type = "disk";
        device = "/dev/by-id/nvme-SHPP41-2000GM_ASC7N440910607A6A_1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1024M";
              type = "EF00";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
      right = {
        type = "disk";
        device = "/dev/by-id/nvme-SHPP41-2000GM_ASC7N440910607A5K_1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1024M";
              type = "EF00";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
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
        metadata = "1.0";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          primary = {
            size = "100%";
            lvm_type = "raid0";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  mountOptions = [ "noatime" ];
                in
                {
                  "/root" = {
                    inherit mountOptions;
                    mountpoint = "/";
                  };
                  "/home" = {
                    inherit mountOptions;
                    mountpoint = "/home";
                  };
                  "/nix" = {
                    mountOptions = [ "compress=zstd" ] ++ mountOptions;
                    mountpoint = "/nix";
                  };
                  "/persist" = {
                    inherit mountOptions;
                    mountpoint = "/persist";
                  };
                  "/log" = {
                    inherit mountOptions;
                    mountpoint = "/var/log";
                  };
                };
            };
          };
        };
      };
    };
  };
}
