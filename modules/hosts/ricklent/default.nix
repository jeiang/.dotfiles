{self, ...}: let
  node = self.lib.legionNodes.ricklent;

  wanInterface = "eth0";
in {
  nixos.configurations.ricklent.module = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [(modulesPath + "/profiles/qemu-guest.nix")];

    disko.devices = lib.mkForce {
      disk.disk1 = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };

    boot = {
      loader.grub = {
        enable = true;
        efiSupport = false;
        extraConfig = ''
          serial --unit=0 --speed=19200 --word=8 --parity=no --stop=1
          terminal_input console serial
          terminal_output console serial
        '';
      };
      kernelParams = ["console=tty0" "console=ttyS0,19200n8" "net.ifnames=0"];
      initrd.availableKernelModules = ["ahci" "sd_mod" "virtio_pci" "virtio_blk" "virtio_scsi"];
    };

    systemd.network.networks."10-wan" = {
      matchConfig.Name = wanInterface;
      address = ["${node.publicIPv6}/128"];
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      dhcpV4Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
    };

    networking = {
      nameservers = ["9.9.9.9" "149.112.112.112"];
      firewall.filterForward = true;
    };

    swapDevices = [{device = "/dev/sdb";}];

    nix.settings = {
      max-jobs = 1;
      cores = 1;
    };
  };
}
