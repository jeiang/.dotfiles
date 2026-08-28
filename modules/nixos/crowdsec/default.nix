_: {
  flake.nixosModules.crowdsec = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.edge.crowdsec;
    sopsFile = ./secrets.yaml;

    # modules/nixos/edge/default.nix hardcodes appsec_url
    # http://127.0.0.1:7422, so 7422 is not a free choice here.
    lapiPort = 8080;
    appsecPort = 7422;

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
  in {
    config = lib.mkIf cfg.enable {
      services.crowdsec = {
        enable = true;

        hub.collections = [
          "crowdsecurity/caddy"
          "crowdsecurity/appsec-virtual-patching" # base-config + vpatch-*, referenced by the local AppSec config
        ];
        # Base parsers caddy-logs depends on, installed directly instead of
        # via the linux collection (which drags in sshd scenarios).
        hub.parsers = [
          "crowdsecurity/syslog-logs"
          "crowdsecurity/geoip-enrich"
          "crowdsecurity/dateparse-enrich"
        ];

        settings = {
          # Must be in confDir (crowdsec-writable via the module's tmpfiles);
          # the DynamicUser StateDirectory root gets permission denied, and
          # enabling the LAPI without a path coerces null at eval.
          lapi.credentialsFile = "/etc/crowdsec/local_api_credentials.yaml";

          general.api.server = {
            enable = true;
            # 0.0.0.0: edge Caddy (loopback) and legion-node2's bouncers
            # (private network) both dial in; the firewall scopes it private.
            listen_uri = "0.0.0.0:${toString lapiPort}";
          };

          # The default loopback bind would be unreachable from node3's
          # cross-node scraper.
          general.prometheus.listen_addr = "0.0.0.0";
        };

        localConfig = {
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
          ];

          parsers.s02Enrich = [
            {
              name = "jeiang/cache-whitelist";
              description = "Do not feed binary cache traffic into ban scenarios";
              whitelist = {
                reason = "binary cache clients legitimately fetch and push in bursts";
                expression = [
                  "evt.Meta.target_fqdn == 'cache.jeiang.dev'"
                  "evt.Meta.target_fqdn == 'cache-push.jeiang.dev'"
                ];
              };
            }
            {
              # The mesh ranges are assigned via the NetBird dashboard and
              # declared nowhere in Nix.
              name = "jeiang/mesh-whitelist";
              description = "Never generate bans against Hetzner private network or NetBird mesh traffic";
              whitelist = {
                reason = "Hetzner private network / NetBird mesh, never bans";
                cidr = [
                  "172.16.0.0/12"
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
      # value Caddy sends as CROWDSEC_LAPI_KEY; the other two are consumed by
      # legion-node2 (modules/nixos/netbird-server/proxy.nix).
      sops.secrets."crowdsec/bouncer-netbird-proxy-key" = {inherit sopsFile;};
      sops.secrets."crowdsec/bouncer-legion-node2-firewall" = {inherit sopsFile;};

      systemd.services = {
        crowdsec-bouncers = {
          description = "Register CrowdSec LAPI bouncer keys";
          after = ["crowdsec.service"];
          wants = ["crowdsec.service"];
          wantedBy = ["multi-user.target"];
          path = [pkgs.gnugrep];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = let
            # Must be the module's cscli wrapper (bakes in -c <store config>
            # plus sudo-to-crowdsec-user); it is only exposed via
            # environment.systemPackages, so invoke the system profile copy.
            cscli = "/run/current-system/sw/bin/cscli";
            registerBouncer = name: keyPath: ''
              if ! ${cscli} bouncers list -o json | grep -q "\"name\": \"${name}\""; then
                ${cscli} bouncers add ${lib.escapeShellArg name} --key "$(cat ${lib.escapeShellArg keyPath})"
              fi
            '';
          in ''
            set -euo pipefail
            ${registerBouncer "edge-caddy" config.sops.secrets."caddy/crowdsec-lapi-key".path}
            ${registerBouncer "netbird-proxy" config.sops.secrets."crowdsec/bouncer-netbird-proxy-key".path}
            ${registerBouncer "legion-node2-firewall" config.sops.secrets."crowdsec/bouncer-legion-node2-firewall".path}
          '';
        };

        crowdsec.serviceConfig.MemoryMax = "512M";

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
