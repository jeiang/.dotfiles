_: {
  # docs/MIGRATION.md piece 1.3: CrowdSec engine (LAPI + log processor +
  # AppSec) for the Edge Node, composed from nixpkgs' first-party
  # services.crowdsec. Imported only for the inventory's edge node
  # (modules/hosts/legion/default.nix), same condition as
  # self.nixosModules.edge, and gated by the same edge.crowdsec.enable
  # switch that module declares (one toggle for the LAPI/AppSec engine and
  # the Caddy handler wiring that consumes it).
  flake.nixosModules.crowdsec = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.edge.crowdsec;

    # k8s-manifests crowdsec/values.yaml lapi.service / appsec service
    # ports; modules/nixos/edge/default.nix already hardcodes
    # appsec_url http://127.0.0.1:7422, so 7422 isn't a free choice here.
    lapiPort = 8080;
    appsecPort = 7422;

    localAppsecConfigName = "jeiang/appsec-caddy";
  in {
    config = lib.mkIf cfg.enable {
      services.crowdsec = {
        enable = true;

        # Hub items installed declaratively via the module's own
        # crowdsec-setup ExecStartPre script (checked
        # nixos/modules/services/security/crowdsec.nix: `cscli collections
        # install`/`cscli parsers install` run at every service start, so
        # this is the module's supported "pin what's installable
        # declaratively" path -- no manual `cscli hub` operator step
        # needed). crowdsecurity/caddy brings the caddy-logs parser +
        # generic HTTP scenarios (verified against
        # https://github.com/crowdsecurity/hub collections/crowdsecurity/caddy.yaml).
        # crowdsecurity/syslog-logs/geoip-enrich/dateparse-enrich are the
        # base parsers caddy-logs' filter depends on (its `evt.Parsed.program`
        # field comes from syslog-logs' "non-syslog" stage) -- normally
        # pulled in by the crowdsecurity/linux collection, installed
        # directly here instead since that collection also drags in sshd
        # scenarios this host doesn't need.
        hub.collections = [
          "crowdsecurity/caddy"
          "crowdsecurity/appsec-virtual-patching" # appsec-rules: base-config + vpatch-*, referenced by the local AppSec config below
        ];
        hub.parsers = [
          "crowdsecurity/syslog-logs"
          "crowdsecurity/geoip-enrich"
          "crowdsecurity/dateparse-enrich"
        ];

        settings.general.api.server = {
          enable = true;
          # 0.0.0.0, not 127.0.0.1 (the module default): edge Caddy's
          # bouncer (loopback) and legion-node2's future netbird-proxy
          # bouncer (piece 3.2, private network) both need to reach this.
          # "Private-interface only" reachability from outside the host is
          # enforced by the firewall, not the bind address -- see the
          # "crowdsec" entry's firewall.scope in
          # modules/hosts/legion/_service-inventory.nix and
          # networking.firewall.trustedInterfaces in
          # modules/hosts/legion/default.nix (enp7s0 is trusted; the
          # public interface never gets an allowedTCPPorts entry for this
          # port).
          listen_uri = "0.0.0.0:${toString lapiPort}";
        };

        # docs/MIGRATION.md piece 6.1: legion-node3's monitoring module
        # scrapes this over the private network, same reachability
        # reasoning (and the same 0.0.0.0-plus-firewall pattern) as
        # listen_uri above -- the module default (127.0.0.1) would make it
        # unreachable from another node. Port matches
        # k8s-manifests/crowdsec/values.yaml `listen_port: 6060`.
        settings.general.prometheus.listen_addr = "0.0.0.0";

        localConfig = {
          acquisitions = [
            {
              # Same file the edge module's Caddy `logFormat` writes
              # (modules/nixos/edge/default.nix): JSON access log, one
              # source of truth for both.
              source = "file";
              filenames = ["${config.services.caddy.logDir}/access.log"];
              labels.type = "caddy";
            }
            {
              # crowdsec-crowdsec-bouncer's `appsec` Caddy handler
              # (modules/nixos/edge/default.nix appsec_url) talks to this.
              source = "appsec";
              listen_addr = "127.0.0.1:${toString appsecPort}";
              path = "/";
              appsec_config = localAppsecConfigName;
              labels.type = "appsec";
            }
          ];

          # Attic exception (docs/MIGRATION.md piece 1.3), mirroring
          # /Users/aidanp/Projects/k8s-manifests/crowdsec/values.yaml's
          # `attic-cache-whitelist` s02-enrich parser whitelist: Attic
          # NAR/narinfo clients (CI runners in particular) legitimately
          # fetch in high-volume bursts that otherwise read as
          # http-crawl/probing. `evt.Meta.target_fqdn` is the field
          # crowdsecurity/caddy-logs sets from the request Host (verified
          # against
          # https://github.com/crowdsecurity/hub parsers/s01-parse/crowdsecurity/caddy-logs.yaml),
          # the Caddy-native equivalent of the cluster's Traefik router-name
          # match.
          parsers.s02Enrich = [
            {
              name = "jeiang/attic-cache-whitelist";
              description = "Do not feed attic binary cache traffic into ban scenarios";
              whitelist = {
                reason = "attic binary cache clients legitimately fetch in bursts";
                expression = ["evt.Meta.target_fqdn == 'attic.jeiang.dev'"];
              };
            }
          ];
        };
      };

      # NetBird stream exclusion (docs/MIGRATION.md piece 1.3), mirroring
      # k8s-manifests crowdsec/README.md's "NetBird AppSec Allow Hook":
      # NetBird's high-churn gRPC/WebSocket routes (the same paths
      # modules/nixos/edge/default.nix's netbird.jeiang.dev block
      # dispatches on) must not be blocked by generic AppSec inspection.
      # services.crowdsec only supports installing *hub* appsec-configs
      # declaratively (services.crowdsec.hub.appSecConfigs); there's no
      # typed option for custom local appsec-config content, so this ships
      # as a raw file at the path cscli itself would install one to
      # (confirmed against crowdsecurity/crowdsec's pkg/cwhub/item.go:
      # APPSEC_CONFIGS = "appsec-configs", installed under
      # services.crowdsec's confDir, /etc/crowdsec/). inband_rules mirror
      # the cluster's crs-vpatch config (base-config + vpatch-*, no
      # out-of-band CRS -- the cluster disabled that ruleset after
      # false-positive decisions on this same NetBird traffic).
      environment.etc."crowdsec/appsec-configs/jeiang-appsec-caddy.yaml".text = ''
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

      # Bouncer keys (docs/MIGRATION.md piece 1.3). The nixos crowdsec
      # module has no declarative `services.crowdsec.bouncers`-style option
      # (checked nixos/modules/services/security/crowdsec.nix); `cscli
      # bouncers add NAME --key <key>` accepts an explicit key, so
      # register both known bouncers idempotently once the LAPI's database
      # exists. The edge Caddy bouncer reuses
      # modules/nixos/edge/default.nix's existing
      # `caddy/crowdsec-lapi-key` secret (same value Caddy sends as
      # CROWDSEC_LAPI_KEY, so registering it here is what makes that key
      # valid). The netbird-proxy bouncer key is new here; piece 3.2 grants
      # legion-node2 access to it via `just sops-updatekeys` and consumes
      # it for the netbird-proxy bouncer client -- an operator step, since
      # its module doesn't exist yet.
      sops.secrets."crowdsec/bouncer-netbird-proxy-key" = {};

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
            registerBouncer = name: keyPath: ''
              if ! cscli bouncers list -o json | grep -q "\"name\": \"${name}\""; then
                cscli bouncers add ${lib.escapeShellArg name} --key "$(cat ${lib.escapeShellArg keyPath})"
              fi
            '';
          in ''
            set -euo pipefail
            ${registerBouncer "edge-caddy" config.sops.secrets."caddy/crowdsec-lapi-key".path}
            ${registerBouncer "netbird-proxy" config.sops.secrets."crowdsec/bouncer-netbird-proxy-key".path}
          '';
        };

        # piece 0.6 capacity audit, docs/MIGRATION.md.
        crowdsec.serviceConfig.MemoryMax = "512M";

        # Fail-open startup ordering (docs/MIGRATION.md Confirmed Decisions
        # and piece 1.3): `wants`+`after`, not `requires` -- Caddy must
        # still start and serve traffic if crowdsec.service is stopped or
        # missing. The hslatman bouncer plugin's own defaults carry the
        # rest of the fail-open posture: `enable_hard_fails` stays
        # unset/false (Caddy doesn't fail to start if the LAPI is
        # unreachable) and modules/nixos/edge/default.nix sets
        # `appsec_fail_open` (AppSec connection errors are ignored, not
        # treated as a block) -- both verified against
        # https://github.com/hslatman/caddy-crowdsec-bouncer crowdsec/caddyfile.go@v0.13.1.
        caddy = lib.mkIf config.services.caddy.enable {
          after = ["crowdsec.service"];
          wants = ["crowdsec.service"];
        };
      };
    };
  };
}
