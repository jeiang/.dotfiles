{self, ...}: let
  mainUnit = "netbird-server";
  dataDir = "/mnt/netbird";

  httpPort = 80;
  serverMetricsPort = 9090;

  stunPort = 3478;
  relayPort = 8080;
  relayMetricsPort = 9091;
  relayHealthPort = 9001;
in {
  legion.services.netbird-server = {
    node = "legion-node2";
    module = "netbird-server";
    stateful = true;
    units = [mainUnit];
    ports = {
      http = httpPort;
      metrics = serverMetricsPort;
    };
    firewall = [
      {
        port = httpPort;
        proto = "tcp";
        scope = "private";
      }
    ];
    volume = {
      name = "legion-netbird";
      mountpoint = dataDir;
      sizeGiB = 10;
      hcloudVolumeId = "106121301";
    };
    backupSet = [dataDir];
  };

  # Started by the netbird-server module above; no module of its own.
  legion.services.netbird-relay = {
    node = "legion-node2";
    units = ["netbird-relay"];
    ports = {
      stun = stunPort;
      relay = relayPort;
      metrics = relayMetricsPort;
      health = relayHealthPort;
    };
    publicHostnames = ["stun.netbird.jeiang.dev"];
    firewall = [
      {
        port = stunPort;
        proto = "udp";
        scope = "public";
      }
      {
        port = relayPort;
        proto = "tcp";
        scope = "private";
      }
    ];
  };

  nixos.modules.netbird-server = {
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
        exposedAddress: "https://netbird.jeiang.dev:443"
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
          - uri: "stun:stun.netbird.jeiang.dev:${toString stunPort}"
            proto: "udp"
        relays:
          addresses:
            - "rels://netbird.jeiang.dev:443"
          secret: "${config.sops.placeholder."netbird/relay-auth-secret"}"
          credentialsTTL: "24h"
        disableAnonymousMetrics: false
        disableGeoliteUpdate: false
        auth:
          # Built-in local auth; a Pocket ID OIDC client exists but the live
          # server config never reads it.
          issuer: "https://netbird.jeiang.dev/oauth2"
          localAuthDisabled: false
          signKeyRefreshEnabled: true
          sessionCookieEncryptionKey: "${config.sops.placeholder."netbird/idp-session-cookie-encryption-key"}"
          dashboardRedirectURIs:
            - "https://netbird.jeiang.dev/nb-auth"
            - "https://netbird.jeiang.dev/nb-silent-auth"
          cliRedirectURIs:
            - "http://localhost:53000/"
        dnsDomain: "jeiang.vpn"
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
            # Advertised address: peers reach the relay through the edge's
            # netbird.jeiang.dev:443 @relay route, not relayPort directly.
            NB_EXPOSED_ADDRESS = "rels://netbird.jeiang.dev:443";
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
}
