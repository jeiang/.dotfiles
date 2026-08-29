_: let
  # Out-of-band rescue path into artemis for when the NetBird mesh cannot
  # bootstrap; depends only on public DNS and static keys.
  artemisPublicKey = "XWfbtRzMfHUrv1oJ0ULRKFTbSn8io1iLkwBcf7AgQwQ=";
  node1PublicKey = "ay1qHJCX2WQONRG5eTfh4fsIcTO6HOU8wdhSwHaJ+BM=";
in {
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
            persistentKeepalive = 25;
            # Without this the peer unit is a one-shot that fails permanently
            # when the boot-time DNS lookup runs before the network is up.
            dynamicEndpointRefreshSeconds = 60;
          }
        ];
      };
      firewall.trustedInterfaces = ["wg-backup"];
    };
  };

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
