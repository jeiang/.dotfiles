{
  self,
  inputs,
  ...
}: {
  nixos.modules.linode = {
    config,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.disko.nixosModules.disko
    ];

    disko.devices.disk.disk1 = {
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
      matchConfig.Name = "eth0";
      address = ["${self.lib.legionNodes.${config.networking.hostName}.publicIPv6}/128"];
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      dhcpV4Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
    };

    networking = {
      nameservers = self.lib.quad9;
      firewall.filterForward = true;
    };

    swapDevices = [{device = "/dev/sdb";}];

    nix.settings = {
      max-jobs = 1;
      cores = 1;
    };
  };
}
