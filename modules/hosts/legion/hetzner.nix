{
  self,
  lib,
  config,
  ...
}: let
  wanInterface = "enp1s0";
  privateInterface = "enp7s0";
  publicV4Gateway = "172.31.1.1";
  publicV6Gateway = "fe80::1";
  privateGateway = "172.16.0.1";

  legionServices = config.legion.services;
in {
  flake.lib = {
    hetznerNodes = lib.filterAttrs (_: node: node.provider == "hetzner") self.lib.legionNodes;

    # Attached Volumes can take /dev/sda; the server disk is always LUN 0.
    hetznerServerDisk = "/dev/disk/by-path/pci-0000:06:00.0-scsi-0:0:0:0";
    hetznerPrivateCidr = "172.16.0.0/12";
    hetznerWanInterface = wanInterface;
    hetznerPrivateInterface = privateInterface;
  };

  nixos.modules.hetzner = {
    config,
    lib,
    ...
  }: let
    node = self.lib.legionNodes.${config.networking.hostName};
  in {
    imports = [self.diskoConfigurations.legion];

    hardware.facter.reportPath = ./facter.json;

    boot.loader.grub.enable = true;

    systemd.network.networks = {
      "10-wan" = {
        matchConfig.Name = wanInterface;
        address = [
          "${node.publicIPv4}/32"
          "${node.publicIPv6}/64"
        ];
        routes = [
          {Destination = "${publicV4Gateway}/32";}
          {
            Gateway = publicV4Gateway;
            GatewayOnLink = true;
          }
          {
            Gateway = publicV6Gateway;
            GatewayOnLink = true;
          }
        ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };

      "20-hcloud-private" = {
        matchConfig.Name = privateInterface;
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.UseRoutes = false;
        routes = [
          {
            Destination = self.lib.hetznerPrivateCidr;
            Gateway = privateGateway;
            GatewayOnLink = true;
          }
        ];
      };
    };

    networking.firewall.trustedInterfaces = [privateInterface];

    # The label is the service name, applied once by the operator; nofail keeps a missing Volume from blocking boot, and mountGuard keeps the service off the unmounted dir.
    fileSystems = lib.listToAttrs (
      lib.mapAttrsToList (name: s:
        lib.nameValuePair s.volume.mountpoint {
          device = "/dev/disk/by-label/${name}";
          fsType = "ext4";
          options = ["nofail" "x-systemd.device-timeout=10s"];
        })
      (lib.filterAttrs (_: s: s.node == config.networking.hostName && s.volume != null) legionServices)
    );
  };
}
