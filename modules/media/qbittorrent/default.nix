{
  self,
  config,
  ...
}: let
  webuiPort = 8081;
  filesPort = 8082;
  torrentingPort = 32881;
  stateDir = "/var/lib/qbittorrent";
  apiKeyFile = "${stateDir}/api-key";
  apiKeyUnit = "qbittorrent-api-key";
  downloadDir = self.lib.mediaDownloadDir;

  exitNode = self.lib.legionNodes.${config.legion.services.qbittorrent-exit.node};
  exitWireguardPort = 51822;
  exitInterface = "wg-qbt";
  exitNamespace = "qbt";
  exitNamespacePath = "/run/netns/${exitNamespace}";
  exitServerIp = "10.101.0.1";
  exitClientIp = "10.101.0.2";
  exitResolvers = self.lib.quad9;

  exitClientPublicKey = "m+sxbQiaqKHzsaroCGK8KUR1DOgo+oUwxSbKkySrbjI=";
  exitServerPublicKey = "hIn9a8Tqq/9BMilfiiUOdP1qDFrAX3VFQslfBARfggw=";
in {
  flake.lib = {
    qbittorrentWebuiPort = webuiPort;
    qbittorrentApiKeyFile = apiKeyFile;
    qbittorrentApiKeyUnit = "${apiKeyUnit}.service";
  };

  legion.services.qbittorrent-exit = {
    node = "ricklent";
    module = "qbittorrent-exit";
    publicPorts = [
      {
        port = exitWireguardPort;
        proto = "udp";
      }
      {
        port = torrentingPort;
        proto = "tcp";
      }
      {
        port = torrentingPort;
        proto = "udp";
      }
    ];
  };

  # Only the Web UI and file listing ride the NetBird interface. Peers reach
  # qBittorrent through the exit node, never through the home network.
  nixos.modules.media = {
    config,
    lib,
    pkgs,
    ...
  }: let
    ip = lib.getExe' pkgs.iproute2 "ip";
    resolvConf = pkgs.writeText "qbittorrent-resolv.conf" (lib.concatMapStringsSep "\n" (n: "nameserver ${n}") exitResolvers + "\n");
    tunnelUnit = "wireguard-${exitInterface}";
    configDir = "${stateDir}/qBittorrent/config";
    # The key goes into the config the unit just reinstalled, read from its
    # file so it never reaches the Nix store or an argument list.
    apiKeyConfig = pkgs.writeShellScript "qbittorrent-api-key-config" ''
      set -eu
      umask 077
      chmod 0700 ${configDir}
      ${lib.getExe pkgs.gawk} -v keyfile=${apiKeyFile} '
        BEGIN { if ((getline key < keyfile) <= 0) exit 1 }
        { print }
        $0 == "[WebUI]" { print "APIKey=" key; added = 1 }
        END { exit !added }
      ' ${configDir}/qBittorrent.conf > ${configDir}/qBittorrent.conf.new
      mv ${configDir}/qBittorrent.conf.new ${configDir}/qBittorrent.conf
    '';
  in {
    persistence.directories = [stateDir];
    monitoredUnits = ["qbittorrent.service" "darkhttpd.service"];

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
          publicKey = exitServerPublicKey;
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
        # The unit reinstalls this file on every start, so the flake owns
        # every preference: a change made in the web UI is lost on the next
        # restart, and gamemode restarts the service for each game.
        serverConfig = {
          LegalNotice.Accepted = true;
          BitTorrent.Session = {
            DefaultSavePath = downloadDir;
            # Stop, never remove: atrium deletes a stopped
            # torrent's files only after it has filed them into the library.
            GlobalMaxRatio = 2;
            GlobalMaxSeedingMinutes = 14 * 24 * 60;
            ShareLimitAction = "Stop";
          };
          # The exit forwards the peer port with a static DNAT.
          Network.PortForwardingEnabled = false;
          # The socket proxy makes every Web UI client loopback, so loopback
          # must authenticate: atrium with the API key, a browser with the
          # temporary password qBittorrent prints to its journal at each start.
          WebUI = {
            LocalHostAuth = true;
            AuthSubnetWhitelistEnabled = false;
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
        inherit (config.services.qbittorrent) user;
        group = self.lib.mediaGroup;
        mode = "0755";
      };

      services = {
        ${apiKeyUnit} = {
          description = "qBittorrent Web API key";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          script = ''
            [ -s ${apiKeyFile} ] && exit 0
            key=$(head -c 21 /dev/urandom | base64 | tr '+/' '-_')
            printf 'qbt_%s' "$key" > ${apiKeyFile}.new
            chown ${config.services.qbittorrent.user} ${apiKeyFile}.new
            chmod 0400 ${apiKeyFile}.new
            mv ${apiKeyFile}.new ${apiKeyFile}
          '';
        };

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
          requires = ["${apiKeyUnit}.service"];
          wants = ["${tunnelUnit}.target"];
          after = ["${tunnelUnit}.service" "${tunnelUnit}.target" "${apiKeyUnit}.service"];
          serviceConfig = {
            ExecStartPre = lib.mkAfter ["${apiKeyConfig}"];
            NetworkNamespacePath = exitNamespacePath;
            UMask = "0002";
            # The namespace has no resolver of its own; the host's would leak
            # lookups to the home network, as would nscd's socket.
            BindReadOnlyPaths = ["${resolvConf}:/etc/resolv.conf"];
            InaccessiblePaths = ["-/run/nscd"];
          };
        };

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

  nixos.modules.qbittorrent-exit = {config, ...}: let
    wanInterface = config.systemd.network.networks."10-wan".matchConfig.Name;
  in {
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
            publicKey = exitClientPublicKey;
            allowedIPs = ["${exitClientIp}/32"];
          }
        ];
      };

      firewall.extraForwardRules = ''
        iifname "${exitInterface}" oifname "${wanInterface}" ip saddr ${exitClientIp} accept
      '';

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
            iifname "${wanInterface}" ip daddr ${exitNode.publicIPv4} meta l4proto { tcp, udp } th dport ${toString torrentingPort} dnat to ${exitClientIp}
          }

          chain post {
            type nat hook postrouting priority srcnat;
            iifname "${exitInterface}" oifname "${wanInterface}" ip saddr ${exitClientIp} masquerade
          }
        '';
      };
    };
  };
}
