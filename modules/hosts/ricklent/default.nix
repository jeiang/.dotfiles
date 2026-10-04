{self, ...}: let
  node = self.lib.legionNodes.ricklent;

  gateway = "10.255.255.1";
  GiB = 1024 * 1024 * 1024;
in {
  nixos.configurations.ricklent.module = {modulesPath, ...}: {
    imports = [(modulesPath + "/profiles/qemu-guest.nix")];

    disko.devices.disk.disk1.device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0";

    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
      initrd.availableKernelModules = ["ahci" "sd_mod"];
    };

    systemd.network.networks."10-wan" = {
      matchConfig.MACAddress = "bc:24:11:d8:a9:02";
      address = ["${node.publicIPv4}/32"];
      routes = [
        {
          Destination = "${gateway}/32";
          Scope = "link";
        }
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
      ];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
    };

    networking.nameservers = ["9.9.9.9" "149.112.112.112"];

    # zram is the primary swap and the swapfile its overflow; min-free/max-free keep builds from filling the 75 GB disk.
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 4 * 1024;
      }
    ];

    nix.settings = {
      max-jobs = 2;
      cores = 2;
      min-free = 8 * GiB;
      max-free = 20 * GiB;
    };
  };
}
