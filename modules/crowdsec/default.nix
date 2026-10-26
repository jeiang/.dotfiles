{self, ...}: let
  lapiPort = 8080;
  metricsPort = 6060;
  appsecPort = 7422;
in {
  legion.services.crowdsec = {
    node = "alda";
    module = "crowdsec";
    units = ["crowdsec" "crowdsec-bouncers" "crowdsec-firewall-bouncer"];
    ports = {
      lapi = lapiPort;
      metrics = metricsPort;
      appsec = appsecPort;
    };
    firewall = [
      {
        port = lapiPort;
        proto = "tcp";
        scope = "private";
      }
      {
        port = metricsPort;
        proto = "tcp";
        scope = "private";
      }
    ];
  };

  nixos.modules.legion.services.crowdsec.settings.config.config_paths.data_dir = "/var/lib/crowdsec/state";

  nixos.modules.crowdsec = {
    config,
    lib,
    pkgs,
    ...
  }: let
    sopsFile = ./secrets.yaml;
    machineSecret = host: "crowdsec/machine-${host}-password";
    bouncerSecret = host: "crowdsec/bouncer-${host}-firewall";

    localAppsecConfigName = "jeiang/appsec-caddy";

    # Local AppSec config: inband vpatch only (out-of-band CRS false-positives
    # on NetBird traffic), with an allow-rule so NetBird's gRPC/WebSocket
    # routes are never blocked. Delivered via tmpfiles, not environment.etc:
    # an etc entry makes appsec-configs/ root-owned and blocks cscli's hub
    # symlink install with "permission denied".
    appsecConfigFile = pkgs.writeText "jeiang-appsec-caddy.yaml" ''
      name: ${localAppsecConfigName}
      default_remediation: ban
      inband_rules:
        - crowdsecurity/base-config
        - crowdsecurity/vpatch-*
      on_match:
        - filter: >-
            req.Host == "netbird.jeiang.dev" &&
            (req.URL.Path startsWith "/signalexchange.SignalExchange/" ||
            req.URL.Path startsWith "/management.ManagementService/" ||
            req.URL.Path startsWith "/management.ProxyService/" ||
            req.URL.Path startsWith "/ws-proxy/")
          apply:
            - CancelEvent()
            - CancelAlert()
            - SetRemediation("allow")
    '';

    bouncerKeys =
      {
        edge-caddy = config.sops.secrets."caddy/crowdsec-lapi-key".path;
        netbird-proxy = config.sops.secrets."crowdsec/bouncer-netbird-proxy-key".path;
        legion-node2-firewall = config.sops.secrets."crowdsec/bouncer-legion-node2-firewall".path;
        netbird-proxy-atl = config.sops.secrets."crowdsec/bouncer-netbird-proxy-atl-key".path;
        garret-firewall = config.sops.secrets.${self.lib.garretFirewallBouncerSecret}.path;
      }
      // lib.mapAttrs' (host: _: lib.nameValuePair "${host}-firewall" config.sops.secrets.${bouncerSecret host}.path) self.lib.crowdsecAgentShards;

    machinePasswords = lib.mapAttrs (host: _: config.sops.secrets.${machineSecret host}.path) self.lib.crowdsecAgentShards;
  in {
    config = {
      services.crowdsec = {
        enable = true;

        hub.collections = [
          "crowdsecurity/caddy"
          "crowdsecurity/appsec-virtual-patching" # base-config + vpatch-*, referenced by the local AppSec config
          "crowdsecurity/sshd"
        ];
        hub.parsers = [
          "crowdsecurity/syslog-logs"
          "crowdsecurity/geoip-enrich"
          "crowdsecurity/dateparse-enrich"
        ];

        settings = {
          config = {
            api.client.credentials_path = "/etc/crowdsec/local_api_credentials.yaml";

            api.server = {
              enable = true;
              # 0.0.0.0: edge Caddy (loopback) and vida's bouncers
              # (private network) both dial in; the firewall scopes it private.
              listen_uri = "0.0.0.0:${toString lapiPort}";
            };

            # The default loopback bind would be unreachable from zantark's
            # cross-node scraper.
            prometheus.listen_addr = "0.0.0.0";
          };

          acquisitions = [
            {
              # The exact file the edge module's Caddy logFormat writes.
              source = "file";
              filenames = ["${config.services.caddy.logDir}/access.log"];
              labels.type = "caddy";
            }
            {
              source = "appsec";
              listen_addr = "127.0.0.1:${toString appsecPort}";
              path = "/";
              appsec_config = localAppsecConfigName;
              labels.type = "appsec";
            }
            {
              source = "journalctl";
              journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
              labels.type = "syslog";
            }
          ];

          parsers.s02Enrich = [
            {
              # The mesh ranges are assigned via the NetBird dashboard and
              # declared nowhere in Nix.
              name = "jeiang/mesh-whitelist";
              description = "Never generate bans against Hetzner private network or NetBird mesh traffic";
              whitelist = {
                reason = "Hetzner private network / NetBird mesh, never bans";
                cidr = [
                  self.lib.hetznerPrivateCidr
                  "100.89.0.0/16"
                  "fd1a:6b4d:62e5:46a::/64"
                ];
              };
            }
          ];
        };
      };

      systemd.tmpfiles.rules = [
        "d /etc/crowdsec/appsec-configs 0750 ${config.services.crowdsec.user} ${config.services.crowdsec.group} -"
        "L+ /etc/crowdsec/appsec-configs/jeiang-appsec-caddy.yaml - - - - ${appsecConfigFile}"
      ];

      # No declarative bouncer option exists upstream, so known bouncer keys
      # are registered idempotently below. The edge-caddy key is the same
      # value Caddy sends as CROWDSEC_LAPI_KEY; the netbird-proxy keys are
      # consumed by modules/netbird-server/proxy.nix, and each agent's bouncer
      # and machine credentials by modules/crowdsec/agent.nix.
      sops.secrets =
        {
          "crowdsec/bouncer-netbird-proxy-key" = {
            inherit sopsFile;
            restartUnits = ["crowdsec-bouncers.service"];
          };
          "crowdsec/bouncer-legion-node2-firewall" = {
            inherit sopsFile;
            restartUnits = ["crowdsec-bouncers.service"];
          };
          "crowdsec/bouncer-netbird-proxy-atl-key" = {
            sopsFile = ./secrets.agent.yaml;
            restartUnits = ["crowdsec-bouncers.service"];
          };
          ${self.lib.garretFirewallBouncerSecret} = {
            sopsFile = ./secrets.garret.yaml;
            restartUnits = ["crowdsec-bouncers.service"];
          };
        }
        // lib.concatMapAttrs (host: sopsFile:
          lib.genAttrs [(bouncerSecret host) (machineSecret host)] (_: {
            inherit sopsFile;
            restartUnits = ["crowdsec-bouncers.service"];
          }))
        self.lib.crowdsecAgentShards;

      # Acts on this node's own decisions, sshd bans included; the edge's Caddy bouncer covers only HTTP.
      services.crowdsec-firewall-bouncer = {
        enable = true;
        settings.mode = "nftables";
        registerBouncer.enable = true;
      };

      systemd.services = {
        crowdsec-bouncers = {
          description = "Register CrowdSec LAPI bouncer keys";
          after = ["crowdsec.service"];
          wants = ["crowdsec.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = config.services.crowdsec.user;
            LoadCredential =
              lib.mapAttrsToList (name: path: "${name}:${path}") bouncerKeys
              ++ lib.mapAttrsToList (name: path: "machine-${name}:${path}") machinePasswords;
          };
          script = let
            cscli = lib.getExe' config.services.crowdsec.package "cscli";
            # Delete-then-add converges the LAPI on the key currently on disk.
            registerBouncer = name: ''
              ${cscli} bouncers delete ${lib.escapeShellArg name} || true
              ${cscli} bouncers add ${lib.escapeShellArg name} --key "$(cat "$CREDENTIALS_DIRECTORY"/${lib.escapeShellArg name})" > /dev/null
            '';
            # --file - keeps the dump off the local credentials file; --force replaces the machine's stored password.
            registerMachine = name: ''
              ${cscli} machines add ${lib.escapeShellArg name} --password "$(cat "$CREDENTIALS_DIRECTORY"/machine-${lib.escapeShellArg name})" --file - --force > /dev/null
            '';
          in
            lib.concatMapStrings registerBouncer (builtins.attrNames bouncerKeys)
            + lib.concatMapStrings registerMachine (builtins.attrNames machinePasswords);
        };

        crowdsec = {
          path = lib.mkForce [config.systemd.package];
          serviceConfig = {
            MemoryMax = "512M";
            SupplementaryGroups = ["systemd-journal"];
          };
        };

        # wants+after, not requires: Caddy must still serve traffic with
        # crowdsec.service stopped or missing (fail-open).
        caddy = lib.mkIf config.services.caddy.enable {
          after = ["crowdsec.service"];
          wants = ["crowdsec.service"];
        };
      };
    };
  };
}
