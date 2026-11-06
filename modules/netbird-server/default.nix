{self, ...}: let
  mainUnit = "netbird-server";
  dataDir = "/mnt/netbird";

  domain = self.lib.netbirdDomain;
  # The edge's @relay route; the server advertises it and the relay announces it, so they must match.
  relayAddress = "rels://${domain}:443";

  httpPort = 80;
  serverMetricsPort = 9090;

  stunPort = 3478;
  relayPort = 8080;
  relayMetricsPort = 9091;
  relayHealthPort = 9001;
in {
  flake.lib = {
    netbirdDomain = "netbird.jeiang.dev";
    netbirdDnsDomain = "jeiang.vpn";
  };

  legion.services = {
    netbird-server = {
      node = "vida";
      module = "netbird-server";
      stateful = true;
      units = [mainUnit];
      ports = {
        http = httpPort;
        metrics = serverMetricsPort;
      };
      volume = {
        name = "legion-netbird";
        mountpoint = dataDir;
        sizeGiB = 10;
        hcloudVolumeId = "106121301";
      };
      backupSet = [dataDir];
    };

    # Started by the netbird-server module above; no module of its own.
    netbird-relay = {
      node = "vida";
      units = ["netbird-relay"];
      ports = {
        stun = stunPort;
        relay = relayPort;
        metrics = relayMetricsPort;
        health = relayHealthPort;
      };
      publicHostnames = ["stun.${domain}"];
      publicPorts = [
        {
          port = stunPort;
          proto = "udp";
        }
      ];
    };
  };

  nixos.modules = {
    netbird-server = {
      config,
      lib,
      pkgs,
      ...
    }: let
      system = pkgs.stdenv.hostPlatform.system;
      serverPkg = self.packages.${system}.netbird-server;
      relayPkg = self.packages.${system}.netbird-relay;

      sopsFile = ./secrets.yaml;

      configYaml = ''
        server:
          listenAddress: ":${toString httpPort}"
          exposedAddress: "https://${domain}:443"
          metricsPort: ${toString serverMetricsPort}
          healthcheckAddress: ":9000"
          logLevel: "info"
          logFile: "console"
          tls:
            certFile: ""
            keyFile: ""
            letsencrypt:
              enabled: false
              dataDir: ""
              domains: []
              email: ""
              awsRoute53: false
          authSecret: "${config.sops.placeholder."netbird/relay-auth-secret"}"
          dataDir: "${dataDir}"
          stuns:
            - uri: "stun:stun.${domain}:${toString stunPort}"
              proto: "udp"
          relays:
            addresses:
              - "${relayAddress}"
            secret: "${config.sops.placeholder."netbird/relay-auth-secret"}"
            credentialsTTL: "24h"
          disableAnonymousMetrics: true
          disableGeoliteUpdate: false
          auth:
            # Everyone signs in through the PocketID identity provider (set up
            # in the management database; its Pocket ID client admits only the
            # `netbird` group). Turning local login back on needs this set to
            # false and a vida deploy; API tokens (nb-nix) work either way.
            issuer: "https://${domain}/oauth2"
            localAuthDisabled: true
            signKeyRefreshEnabled: true
            sessionCookieEncryptionKey: "${config.sops.placeholder."netbird/idp-session-cookie-encryption-key"}"
            dashboardRedirectURIs:
              - "https://${domain}/nb-auth"
              - "https://${domain}/nb-silent-auth"
            cliRedirectURIs:
              - "http://localhost:53000/"
          dnsDomain: "${self.lib.netbirdDnsDomain}"
          store:
            engine: "sqlite"
            dsn: ""
            encryptionKey: "${config.sops.placeholder."netbird/store-encryption-key"}"
      '';
    in {
      sops = {
        secrets = {
          "netbird/store-encryption-key" = {inherit sopsFile;};
          "netbird/relay-auth-secret" = {inherit sopsFile;};
          "netbird/idp-session-cookie-encryption-key" = {inherit sopsFile;};
        };

        templates = {
          "netbird-server-config.yaml" = {
            owner = "netbird";
            group = "netbird";
            restartUnits = ["${mainUnit}.service"];
            content = configYaml;
          };

          "netbird-relay.env" = {
            restartUnits = ["netbird-relay.service"];
            content = "NB_AUTH_SECRET=${config.sops.placeholder."netbird/relay-auth-secret"}\n";
          };
        };
      };

      users.groups.netbird = {};
      users.users.netbird = {
        isSystemUser = true;
        group = "netbird";
      };

      systemd = {
        services = {
          # mountGuard: never silently initialize a fresh sqlite store on the
          # root disk when the Volume is missing or late.
          ${mainUnit} =
            lib.recursiveUpdate
            {
              description = "NetBird unified management/signal server";
              after = ["network-online.target"];
              wants = ["network-online.target"];
              wantedBy = ["multi-user.target"];
              serviceConfig = {
                ExecStart = "${lib.getExe serverPkg} --config ${config.sops.templates."netbird-server-config.yaml".path}";
                Restart = "on-failure";
                RestartSec = 5;
                User = "netbird";
                Group = "netbird";
                AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
                MemoryMax = "320M";
              };
            }
            (self.lib.mountGuard dataDir {
              inherit pkgs;
              owner = "netbird";
              mode = "0750";
            });

          netbird-relay = {
            description = "NetBird relay + STUN server";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            wantedBy = ["multi-user.target"];
            environment = {
              NB_LISTEN_ADDRESS = ":${toString relayPort}";
              # Advertised address: peers reach the relay through the edge, not relayPort directly.
              NB_EXPOSED_ADDRESS = relayAddress;
              NB_ENABLE_STUN = "true";
              NB_STUN_PORTS = toString stunPort;
              NB_LOG_LEVEL = "info";
              NB_METRICS_PORT = toString relayMetricsPort;
              NB_HEALTH_LISTEN_ADDRESS = ":${toString relayHealthPort}";
            };
            serviceConfig = {
              ExecStart = lib.getExe relayPkg;
              EnvironmentFile = [config.sops.templates."netbird-relay.env".path];
              Restart = "on-failure";
              RestartSec = 5;
              DynamicUser = true;
              MemoryMax = "96M";
            };
          };
        };
      };
    };
  };
}
