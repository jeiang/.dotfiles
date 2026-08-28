{self, ...}: {
  flake.nixosModules.netbird-server = {
    config,
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    serverPkg = self.packages.${system}.netbird-server;
    relayPkg = self.packages.${system}.netbird-relay;

    dataDir = "/mnt/netbird";

    sopsFile = ./secrets.yaml;

    relayPort = self.lib.ports.legion-node2.netbird-relay;
    stunPort = self.lib.ports.legion-node2.netbird-stun;
    metricsPort = 9091;
    healthcheckPort = 9001;

    configYaml = ''
      server:
        listenAddress: ":${toString self.lib.ports.legion-node2.netbird-http}"
        exposedAddress: "https://netbird.jeiang.dev:443"
        metricsPort: ${toString self.lib.ports.legion-node2.netbird-server-metrics}
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
          restartUnits = ["netbird-server.service"];
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
        netbird-server =
          {
            description = "NetBird unified management/signal server";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              ExecStart = "${lib.getExe serverPkg} --config ${config.sops.templates."netbird-server-config.yaml".path}";
              # An ExecStartPre, NOT tmpfiles: tmpfiles-setup is not ordered
              # after the Volume mount, so a first-mount activation would
              # have its work hidden; `+` runs it as root despite User=.
              ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o netbird -g netbird -m 0750 ${dataDir}";
              Restart = "on-failure";
              RestartSec = 5;
              User = "netbird";
              Group = "netbird";
              AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
              MemoryMax = "320M";
            };
          }
          // self.lib.mountGuard dataDir;

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
            NB_METRICS_PORT = toString metricsPort;
            NB_HEALTH_LISTEN_ADDRESS = ":${toString healthcheckPort}";
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
