{
  inputs,
  self,
  lib,
  ...
}: let
  legionNodeNames = builtins.attrNames self.lib.legionNodes;

  mkMeshInterface = address: {
    wt0 = {
      network = "netbird";
      addresses = [address];
      virtual = true;
      type = "wireguard";
    };
  };

  mkBackupTunnelInterface = host: {
    wg-backup = {
      network = "wg-backup";
      addresses = self.nixosConfigurations.${host}.config.networking.wireguard.interfaces.wg-backup.ips;
      virtual = true;
      type = "wireguard";
    };
  };
in {
  imports = [inputs.nix-topology.flakeModule];

  nixos.modules.base.imports = [inputs.nix-topology.nixosModules.default];

  perSystem.topology.modules = [
    ({config, ...}: let
      inherit (config.lib.topology) mkConnection mkDevice mkInternet;
    in {
      networks = {
        netbird.name = "NetBird mesh";
        hetzner-private = {
          name = "Hetzner private network";
          cidrv4 = self.lib.hetznerPrivateCidr;
        };
        home.name = "Home LAN";
        wg-backup.name = "WireGuard backup tunnel";
      };

      nodes = lib.mkMerge [
        (lib.mapAttrs (_: address: {interfaces = mkMeshInterface address;}) self.lib.netbirdPeers)
        (lib.genAttrs legionNodeNames (_: {interfaces.enp7s0.network = "hetzner-private";}))
        {
          internet = mkInternet {
            connections = map (node: mkConnection node "enp1s0") legionNodeNames;
          };

          artemis.interfaces =
            {
              enp16s0.network = "home";
            }
            // lib.recursiveUpdate (mkBackupTunnelInterface "artemis") {
              wg-backup.physicalConnections = [(mkConnection "legion-node1" "wg-backup")];
            };

          legion-node1.interfaces = mkBackupTunnelInterface "legion-node1";

          # nix-topology has no darwin module, so zakkart cannot self-describe.
          zakkart = mkDevice "zakkart" {
            info = "MacBook";
            interfaces.wt0 = {
              network = "netbird";
              virtual = true;
              type = "wireguard";
            };
          };
        }
      ];
    })
  ];
}
