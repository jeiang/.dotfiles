_: let
  # Static keypair per endpoint, private halves in ./secrets.yaml. The
  # tunnel exists for exactly one failure mode: artemis reboots while the
  # self-hosted NetBird management server is down, in which case the netbird
  # client cannot bootstrap any peer connection from cache (see
  # docs/research/netbird-client-resilience.md) and the mesh is unreachable
  # until management returns. This link depends on nothing but public DNS
  # and static keys: node1.jeiang.dev -> ssh -> 10.100.0.2.
  artemisPublicKey = "XWfbtRzMfHUrv1oJ0ULRKFTbSn8io1iLkwBcf7AgQwQ=";
  node1PublicKey = "ay1qHJCX2WQONRG5eTfh4fsIcTO6HOU8wdhSwHaJ+BM=";
in {
  # artemis: initiator. Behind home NAT, so it dials out and keeps the
  # mapping alive; nothing listens publicly on this side.
  flake.nixosModules.backupTunnel = {config, ...}: {
    sops.secrets."wireguard/artemis-private-key".sopsFile = ./secrets.yaml;

    networking = {
      wireguard.interfaces.wg-backup = {
        ips = ["10.100.0.2/30"];
        privateKeyFile = config.sops.secrets."wireguard/artemis-private-key".path;
        peers = [
          {
            publicKey = node1PublicKey;
            allowedIPs = ["10.100.0.1/32"];
            endpoint = "node1.jeiang.dev:51821";
            # Keeps the NAT mapping open so node1 can reach back in when
            # the mesh is down.
            persistentKeepalive = 25;
            # Makes the peer unit long-running with periodic endpoint
            # re-resolution instead of a one-shot: at boot the endpoint's
            # DNS lookup can run before the network is up, and without
            # this the unit fails permanently and the tunnel never forms
            # (bit the first post-deploy reboot, 2026-08-16).
            dynamicEndpointRefreshSeconds = 60;
          }
        ];
      };
      # SSH in from node1 rides this interface; same trust model as the
      # netbird interface (modules/nixos/netbird.nix).
      firewall.trustedInterfaces = ["wg-backup"];
    };
  };

  # legion-node1: responder. Placed via the service inventory
  # (modules/hosts/legion/_service-inventory.nix "backup-tunnel"), which
  # also opens UDP 51821 on the host firewall. The Hetzner Cloud Firewall
  # is a manual per-port gate (inventory header comment) -- the runbook
  # covers opening it there.
  flake.nixosModules.backupTunnelResponder = {config, ...}: {
    sops.secrets."wireguard/node1-private-key".sopsFile = ./secrets.yaml;

    networking.wireguard.interfaces.wg-backup = {
      ips = ["10.100.0.1/30"];
      listenPort = 51821;
      privateKeyFile = config.sops.secrets."wireguard/node1-private-key".path;
      peers = [
        {
          publicKey = artemisPublicKey;
          allowedIPs = ["10.100.0.2/32"];
        }
      ];
    };
  };
}
