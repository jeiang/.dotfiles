{
  self,
  config,
  ...
}: let
  # Out-of-band rescue path into artemis for when the NetBird mesh cannot
  # bootstrap; depends only on public DNS and static keys.
  artemisPublicKey = "XWfbtRzMfHUrv1oJ0ULRKFTbSn8io1iLkwBcf7AgQwQ=";
  responderPublicKey = "ay1qHJCX2WQONRG5eTfh4fsIcTO6HOU8wdhSwHaJ+BM=";
  artemisAddress = "10.100.0.2";
  responderAddress = "10.100.0.1";
  wireguardPort = 51821;
  responderNode = config.legion.services.backup-tunnel.node;
in {
  legion.services.backup-tunnel = {
    node = "alda";
    module = "backup-tunnel-responder";
    publicPorts = [
      {
        port = wireguardPort;
        proto = "udp";
      }
    ];
  };

  nixos.modules.artemis = {config, ...}: {
    monitoredUnits = ["wireguard-wg-backup.service"];

    sops.secrets."wireguard/artemis-private-key" = {
      sopsFile = ./secrets.yaml;
      restartUnits = ["wireguard-wg-backup.service"];
    };

    networking = {
      wireguard.interfaces.wg-backup = {
        ips = ["${artemisAddress}/30"];
        privateKeyFile = config.sops.secrets."wireguard/artemis-private-key".path;
        peers = [
          {
            publicKey = responderPublicKey;
            allowedIPs = ["${responderAddress}/32"];
            endpoint = "${self.lib.nodeHostname responderNode}:${toString wireguardPort}";
            persistentKeepalive = 25;
            # Without this the peer unit is a one-shot that fails permanently
            # when the boot-time DNS lookup runs before the network is up.
            dynamicEndpointRefreshSeconds = 60;
          }
        ];
      };
      firewall.interfaces.wg-backup.allowedTCPPorts = [22];
    };
  };

  nixos.modules.backup-tunnel-responder = {config, ...}: {
    sops.secrets."wireguard/node1-private-key" = {
      sopsFile = ./secrets.yaml;
      restartUnits = ["systemd-networkd.service"];
    };

    # networkd starts before sysinit.target and loads this key as a credential;
    # without the key file it fails with 243/CREDENTIALS and the node boots
    # with no network.
    systemd.services.sops-install-secrets.before = ["systemd-networkd.service"];

    networking.wireguard.interfaces.wg-backup = {
      ips = ["${responderAddress}/30"];
      listenPort = wireguardPort;
      privateKeyFile = config.sops.secrets."wireguard/node1-private-key".path;
      peers = [
        {
          publicKey = artemisPublicKey;
          allowedIPs = ["${artemisAddress}/32"];
        }
      ];
    };
  };
}
