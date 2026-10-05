{self, ...}: let
  webuiPort = 8081;
  filesPort = 8082;
  torrentingPort = 42881;
  stateDir = "/var/lib/qbittorrent";
  downloadDir = self.lib.mediaDownloadDir;

  exitNode = self.lib.legionNodes.ricklent;
  exitWireguardPort = 51822;
  exitInterface = "wg-qbt";
  exitNamespace = "qbt";
  exitNamespacePath = "/run/netns/${exitNamespace}";
  exitServerIp = "10.101.0.1";
  exitClientIp = "10.101.0.2";
  exitResolvers = ["9.9.9.9" "149.112.112.112"];

  artemisExitPublicKey = "m+sxbQiaqKHzsaroCGK8KUR1DOgo+oUwxSbKkySrbjI=";
  ricklentExitPublicKey = "hIn9a8Tqq/9BMilfiiUOdP1qDFrAX3VFQslfBARfggw=";
in {
  legion.services.qbittorrent-exit = {
    node = "ricklent";
    module = "qbittorrent-exit";
    ports = {
      wireguard = exitWireguardPort;
      peer = torrentingPort;
    };
    firewall = [
      {
        port = exitWireguardPort;
        proto = "udp";
        scope = "public";
      }
      {
        port = torrentingPort;
        proto = "tcp";
        scope = "public";
      }
      {
        port = torrentingPort;
        proto = "udp";
        scope = "public";
      }
    ];
  };

  # Only the Web UI and file listing ride the NetBird interface, which is
  # already trusted (modules/netbird.nix). Peers reach qBittorrent through
  # ricklent, never through the home network.
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    ip = lib.getExe' pkgs.iproute2 "ip";
    resolvConf = pkgs.writeText "qbittorrent-resolv.conf" (lib.concatMapStringsSep "\n" (n: "nameserver ${n}") exitResolvers + "\n");
    tunnelUnit = "wireguard-${exitInterface}";
  in {
    persistence.directories = [stateDir];

    # Seeding would eat the uplink a remote Moonlight session needs.
    gaming.pauseUnits = ["qbittorrent.service"];

    sops.secrets."wireguard/qbittorrent-private-key" = {
      sopsFile = ./secrets.yaml;
      restartUnits = ["${tunnelUnit}.service"];
    };

    # The tunnel interface is the namespace's only link besides loopback, so
    # qBittorrent has no route when the tunnel is down.
    networking.wireguard.interfaces.${exitInterface} = {
      ips = ["${exitClientIp}/30"];
      privateKeyFile = config.sops.secrets."wireguard/qbittorrent-private-key".path;
      interfaceNamespace = exitNamespace;
      peers = [
        {
          publicKey = ricklentExitPublicKey;
          allowedIPs = ["0.0.0.0/0"];
          # `wg` resolves the endpoint inside the namespace, where no resolver is reachable before the tunnel is up.
          endpoint = "${exitNode.publicIPv4}:${toString exitWireguardPort}";
          persistentKeepalive = 25;
        }
      ];
    };

    services = {
      qbittorrent = {
        enable = true;
        inherit webuiPort torrentingPort;
        group = self.lib.mediaGroup;
        profileDir = stateDir;
        openFirewall = false;
        # The unit reinstalls this file on every start, so the flake owns
        # every preference: a change made in the web UI is lost on the next
        # restart, and gamemode restarts the service for each game.
        serverConfig = {
          LegalNotice.Accepted = true;
          BitTorrent.Session.DefaultSavePath = downloadDir;
          # The exit forwards the peer port with a static DNAT.
          Network.PortForwardingEnabled = false;
          Preferences.WebUI = {
            # Every Web UI connection arrives from the socket proxy on the
            # namespace's loopback; the firewall is the real boundary.
            # Without a match qBittorrent logs a single-use password at each
            # start.
            AuthSubnetWhitelistEnabled = true;
            AuthSubnetWhitelist = "127.0.0.1/32";
          };
        };
      };

      darkhttpd = {
        enable = true;
        # The module always adds --ipv6, which makes darkhttpd parse --addr as
        # an IPv6 literal; it clears IPV6_V6ONLY, so :: also takes IPv4.
        address = "::";
        port = filesPort;
        rootDir = downloadDir;
      };
    };

    # World-readable, because darkhttpd runs under a DynamicUser that is in no
    # group of ours.
    systemd = {
      tmpfiles.settings.qbittorrent-downloads.${downloadDir}.d = {
        user = "qbittorrent";
        group = self.lib.mediaGroup;
        mode = "0755";
      };

      services = {
        qbittorrent-netns = {
          description = "Network namespace for qBittorrent";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = [
              "${ip} netns add ${exitNamespace}"
              "${ip} -n ${exitNamespace} link set lo up"
            ];
            ExecStop = "${ip} netns delete ${exitNamespace}";
          };
        };

        ${tunnelUnit} = {
          bindsTo = ["qbittorrent-netns.service"];
          after = ["qbittorrent-netns.service"];
        };

        qbittorrent = {
          bindsTo = ["${tunnelUnit}.service"];
          wants = ["${tunnelUnit}.target"];
          after = ["${tunnelUnit}.service" "${tunnelUnit}.target"];
          serviceConfig = {
            NetworkNamespacePath = exitNamespacePath;
            UMask = "0002";
            # The namespace has no resolver of its own; the host's would leak
            # lookups to the home network, as would nscd's socket.
            BindReadOnlyPaths = ["${resolvConf}:/etc/resolv.conf"];
            InaccessiblePaths = ["-/run/nscd"];
          };
        };

        # Forwards host-namespace connections to the Web UI inside the namespace.
        qbittorrent-webui = {
          description = "qBittorrent Web UI proxy";
          bindsTo = ["qbittorrent-netns.service"];
          after = ["qbittorrent-netns.service"];
          serviceConfig = {
            ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString webuiPort}";
            NetworkNamespacePath = exitNamespacePath;
            DynamicUser = true;
            PrivateTmp = true;
          };
        };
      };

      sockets.qbittorrent-webui = {
        description = "qBittorrent Web UI";
        wantedBy = ["sockets.target"];
        listenStreams = [(toString webuiPort)];
      };
    };
  };

  nixos.modules.qbittorrent-exit = {config, ...}: {
    sops.secrets."wireguard/qbittorrent-private-key" = {
      sopsFile = ./secrets.exit.yaml;
      restartUnits = ["systemd-networkd.service"];
    };

    # networkd starts before sysinit.target and loads this key as a credential;
    # without the key file it fails with 243/CREDENTIALS and the node boots
    # with no network.
    systemd.services.sops-install-secrets.before = ["systemd-networkd.service"];

    networking = {
      wireguard.interfaces.${exitInterface} = {
        ips = ["${exitServerIp}/30"];
        listenPort = exitWireguardPort;
        privateKeyFile = config.sops.secrets."wireguard/qbittorrent-private-key".path;
        peers = [
          {
            publicKey = artemisExitPublicKey;
            allowedIPs = ["${exitClientIp}/32"];
          }
        ];
      };

      # The global firewall opens ports on every untrusted interface, so the
      # tunnel would reach sshd; only forwarded traffic may cross it.
      nftables.tables.qbittorrent-exit-input = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority filter - 1; policy accept;
            iifname "${exitInterface}" drop
          }
        '';
      };

      nftables.tables.qbittorrent-exit = {
        family = "ip";
        content = ''
          chain pre {
            type nat hook prerouting priority dstnat;
            ip daddr ${exitNode.publicIPv4} meta l4proto { tcp, udp } th dport ${toString torrentingPort} dnat to ${exitClientIp}
          }

          chain post {
            type nat hook postrouting priority srcnat;
            iifname "${exitInterface}" oifname != "${exitInterface}" masquerade
          }
        '';
      };
    };
  };
}
