{
  self,
  inputs,
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
    imports = [inputs.disko.nixosModules.disko];

    disko.devices = {
      disk.disk1 = {
        device = self.lib.hetznerServerDisk;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            esp = {
              name = "ESP";
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
      lvm_vg.pool = {
        type = "lvm_vg";
        lvs.root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["defaults"];
          };
        };
      };
    };

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

    networking = {
      firewall.interfaces.${privateInterface} = let
        ports =
          [config.services.prometheus.exporters.node.port]
          ++ lib.concatMap (s: builtins.attrValues s.ports) (builtins.filter (s: s.node == config.networking.hostName) (builtins.attrValues legionServices));
      in {
        allowedTCPPorts = ports;
        allowedUDPPorts = ports;
      };

      # A NetBird exit route forwards its sources to any destination, this network and the metadata service included.
      # NetBird puts an accept for its interface at the head of every forward and input chain, so the drop is in prerouting.
      nftables.tables.private-network-guard = {
        family = "ip";
        content = ''
          chain prerouting {
            type filter hook prerouting priority filter; policy accept;
            iifname "${config.services.netbird.clients.default.interface}" ip daddr { ${self.lib.hetznerPrivateCidr}, 169.254.0.0/16 } drop
          }
        '';
      };
    };

    # The label is the service name, applied once by the operator; nofail keeps a missing Volume from blocking boot.
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
