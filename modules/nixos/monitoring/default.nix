_: {
  # docs/MIGRATION.md piece 6.1: monitoring composition module for
  # legion-node3 (VictoriaMetrics, VictoriaLogs, Grafana, vmalert,
  # Alertmanager). Local composition module (DESIGN.md Service Ownership):
  # several first-party modules configured as one service boundary.
  # Imported only for the inventory node placing `monitoring`
  # (modules/hosts/legion/default.nix, legion-node3 today, same
  # optional-import pattern as modules/nixos/blocky.nix). Fleet-wide bits
  # this module depends on (node_exporter, journald log shipping to this
  # node's VictoriaLogs) live in modules/hosts/legion/default.nix's
  # legionConfiguration instead, per docs/MIGRATION.md's "fleet-wide bits
  # ... go in legionConfiguration" instruction -- they're not "placed"
  # services owned by a single inventory entry.
  #
  # Reset allowed (docs/MIGRATION.md Confirmed Decisions): all state below
  # is node-local disposable storage under /var/lib (systemd's
  # StateDirectory mechanism, services.victoriametrics/victorialogs have no
  # option to point elsewhere) -- no Hetzner Volume, no backupSet, matching
  # the `monitoring` inventory entry (modules/hosts/legion/_service-inventory.nix,
  # `stateful = false`).
  flake.nixosModules.monitoring = {
    config,
    pkgs,
    ...
  }: let
    # Legion private-network addresses (modules/hosts/legion/default.nix
    # `legionNodes`) for the scrape targets this module reaches on other
    # nodes. Not importable directly (that file's `legionNodes` is a local
    # `let` binding, not a flake output) -- same duplication
    # modules/nixos/edge/default.nix already accepts for its own node2/
    # node3/node4 consts.
    node1 = "172.17.0.1"; # Edge: Caddy admin/metrics, CrowdSec metrics
    node2 = "172.17.0.2"; # NetBird server metrics
    legionPrivateIPs = [
      "172.17.0.1"
      "172.17.0.2"
      "172.17.0.3"
      "172.17.0.4"
      "172.17.0.6" # legion-node5 (private address gap at .5 is intentional, DESIGN.md)
    ];

    vmPort = 8428; # services.victoriametrics default listenAddress
    vlPort = 9428; # services.victorialogs default listenAddress

    # docs/MIGRATION.md piece 6.1 chart mirror: k8s-manifests
    # monitoring/values.yaml vmsingle/vlsingle both set
    # `spec.retentionPeriod: "1"` (one month -- VictoriaMetrics/VictoriaLogs
    # count an unsuffixed retentionPeriod in months). Neither
    # nixpkgs-pinned module accepts a bare "1" typed differently, so both
    # get the identical string.
    retentionPeriod = "1";

    dashboardsDir = pkgs.linkFarm "grafana-dashboards" [
      {
        # k8s-manifests/crowdsec/crowdsec-vmservicescrape.yaml scrapes
        # CrowdSec at :6060/metrics (mirrored below); this is the matching
        # dashboard the plan carries, extracted from
        # k8s-manifests/monitoring/crowdsec-dashboard-configmap.yaml's
        # embedded `crowdsec.json` (its own `data:`/YAML wrapper stripped,
        # JSON body unchanged) -- no other dashboard is carried: the chart
        # relies on the upstream vm/victoria-metrics-k8s-stack's bundled
        # sidecar-loaded dashboards for node/VM visibility, which
        # values.yaml never pins to specific IDs, so there is nothing
        # concrete to reproduce here (gap noted in
        # docs/runbooks/monitoring-cutover.md).
        name = "crowdsec.json";
        path = ./crowdsec-dashboard.json;
      }
    ];
  in {
    services = {
      victoriametrics = {
        enable = true;
        inherit retentionPeriod;
        prometheusConfig.scrape_configs = [
          {
            # Fleet-wide node_exporter (modules/hosts/legion/default.nix
            # legionConfiguration enables services.prometheus.exporters.node
            # on every node, port 9100 default). Reachable over the
            # private network the same way every other cross-node backend
            # in this repo is: trustedInterfaces (enp7s0), never opened
            # publicly.
            job_name = "node";
            static_configs = [
              {
                targets = map (ip: "${ip}:9100") legionPrivateIPs;
                labels.type = "node";
              }
            ];
          }
          {
            # modules/nixos/edge/default.nix's dedicated metrics site
            # block (port 2020, not Caddy's admin API -- that stays
            # localhost-only, deliberately not exposed cross-node; see
            # that module's comment).
            job_name = "caddy";
            static_configs = [
              {
                targets = ["${node1}:2020"];
                labels.type = "edge";
              }
            ];
          }
          {
            # modules/nixos/crowdsec/default.nix's engine, prometheus
            # section (default enabled, port 6060, matches
            # k8s-manifests/crowdsec/values.yaml `listen_port: 6060` and
            # its VMServiceScrape's `path: /metrics`). Only populated once
            # `edge.crowdsec.enable` flips true
            # (docs/runbooks/edge-cutover.md "CrowdSec enablement") --
            # until then this target legitimately reads down, same as the
            # edge's own routes that 502 pre-cutover elsewhere in this
            # repo.
            job_name = "crowdsec";
            static_configs = [
              {
                targets = ["${node1}:6060"];
                labels.type = "edge";
              }
            ];
          }
          {
            # modules/nixos/netbird-server/default.nix's unified server,
            # `metricsPort: 9090` in its rendered config.yaml
            # (k8s-manifests/netbird/values.yaml `server.metricsPort:
            # 9090` is the only metrics port the chart configures -- the
            # relay has no matching chart-side scrape config, so none is
            # added here either).
            job_name = "netbird-server";
            static_configs = [
              {
                targets = ["${node2}:9090"];
                labels.type = "netbird";
              }
            ];
          }
          {
            # modules/nixos/blocky.nix: same node, no explicit prometheus
            # section (metrics ride the existing `ports.http` listener,
            # per that module's own comment).
            job_name = "blocky";
            static_configs = [
              {
                targets = ["127.0.0.1:8000"];
                labels.type = "dns";
              }
            ];
          }
        ];
      };

      victorialogs = {
        enable = true;
        # No native retentionPeriod option (unlike victoriametrics above);
        # VictoriaLogs accepts the identical CLI flag via extraOptions.
        extraOptions = ["-retentionPeriod=${retentionPeriod}"];
      };

      grafana = {
        enable = true;
        settings = {
          server = {
            # http_addr left at the module default ("", all interfaces):
            # same private-only-via-firewall reachability pattern as every
            # other cross-node backend in this repo
            # (modules/nixos/blocky.nix comment). Port 3000 matches
            # modules/nixos/edge/default.nix's existing grafana.jeiang.dev
            # route (`reverse_proxy ${node3}:3000`).
            domain = "grafana.jeiang.dev";
            root_url = "https://grafana.jeiang.dev";
          };
          auth = {
            disable_login_form = true;
            oauth_auto_login = true;
          };
          security = {
            # nixpkgs 26.05 dropped the module's built-in default for this
            # (used to encrypt secrets Grafana itself stores in its DB,
            # e.g. datasource credentials) -- it now asserts a value is
            # set. Grafana's own "file provider" syntax
            # (`$__file{path}`) reads the value from a file at runtime, so
            # only the sops secret's path -- not its content -- ends up in
            # this Nix-store-rendered ini, consistent with every other
            # secret in this module.
            secret_key = "$__file{${config.sops.secrets."grafana/secret-key".path}}";
          };
          # Pocket ID generic OAuth (k8s-manifests monitoring/values.yaml
          # `grafana.grafana.ini."auth.generic_oauth"`, client id
          # unchanged -- carried as-is, not a secret). client_secret is
          # deliberately absent here: delivered via
          # GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET in the sops-templated
          # environment file below instead of the Nix-store-rendered ini
          # (DESIGN.md State And Backup Boundaries: runtime secrets via
          # sops, never in the store).
          "auth.generic_oauth" = {
            enabled = true;
            name = "Pocket ID";
            allow_sign_up = true;
            client_id = "a70e6d0d-360c-415f-b154-85ec7a6bc352";
            scopes = "openid profile email groups";
            auth_url = "https://auth.jeiang.dev/authorize";
            token_url = "https://auth.jeiang.dev/api/oidc/token";
            api_url = "https://auth.jeiang.dev/api/oidc/userinfo";
            login_attribute_path = "preferred_username";
            name_attribute_path = "name";
            email_attribute_path = "email";
            role_attribute_path = "contains(groups[*], 'monitoring_admin') && 'Admin' || contains(groups[*], 'monitoring_editor') && 'Editor' || contains(groups[*], 'monitoring_reader') && 'Viewer'";
            role_attribute_strict = true;
          };
        };

        # VictoriaMetrics implements the Prometheus HTTP API directly, so
        # Grafana's built-in "prometheus" datasource type works against it
        # unmodified -- no plugin needed, and it keeps the carried
        # CrowdSec dashboard's `${datasource}` template variable (which
        # filters on `query: "prometheus"`, k8s-manifests/crowdsec's
        # dashboard JSON) working without changes. VictoriaLogs has no
        # built-in Grafana datasource type, so its dedicated community
        # plugin is still needed (declarativePlugins below).
        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "VictoriaMetrics";
              type = "prometheus";
              url = "http://127.0.0.1:${toString vmPort}";
              isDefault = true;
            }
            {
              name = "VictoriaLogs";
              type = "victoriametrics-logs-datasource";
              url = "http://127.0.0.1:${toString vlPort}";
            }
          ];
          dashboards.settings.providers = [
            {
              name = "default";
              options.path = dashboardsDir;
            }
          ];
        };
        declarativePlugins = [pkgs.grafanaPlugins.victoriametrics-logs-datasource];
      };

      # vmalert: rules evaluated against this node's own VictoriaMetrics,
      # notifications sent to this node's own Alertmanager (both loopback,
      # same node). docs/MIGRATION.md piece 6.1: the chart's own alerting
      # relied on the upstream vm/victoria-metrics-k8s-stack's bundled
      # `defaultRules` (dozens of Kubernetes-specific rule groups, none of
      # which apply to a single host-native node) plus nothing of its own
      # (k8s-manifests monitoring/values.yaml has no `vmalert.spec.rules`
      # override) -- there is no concrete rule set to carry 1:1. This
      # starts with the minimal meaningful set docs/MIGRATION.md's
      # fallback describes (instance/service down, disk pressure, memory
      # pressure); gap and upgrade path noted in
      # docs/runbooks/monitoring-cutover.md.
      vmalert.instances.default = {
        enable = true;
        settings = {
          "datasource.url" = "http://127.0.0.1:${toString vmPort}";
          "notifier.url" = ["http://127.0.0.1:9093"];
        };
        rules.groups = [
          {
            name = "fleet-health";
            rules = [
              {
                alert = "TargetDown";
                expr = "up == 0";
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "{{ $labels.job }} target down on {{ $labels.instance }}";
                  description = "{{ $labels.instance }} (job {{ $labels.job }}) has been unreachable for 5 minutes.";
                };
              }
              {
                alert = "HighDiskUsage";
                expr = ''100 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"} * 100) > 90'';
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Disk usage above 90% on {{ $labels.instance }}";
                  description = "{{ $labels.mountpoint }} on {{ $labels.instance }} is over 90% full.";
                };
              }
              {
                alert = "HighMemoryUsage";
                expr = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 90";
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Memory usage above 90% on {{ $labels.instance }}";
                  description = "{{ $labels.instance }} has used over 90% of memory for 10 minutes.";
                };
              }
            ];
          }
        ];
      };

      # Alertmanager: existing Discord webhook retained
      # (docs/MIGRATION.md Confirmed Decisions "Alerting is retained"),
      # routing/grouping copied from k8s-manifests
      # monitoring/values.yaml `alertmanager.config`.
      prometheus.alertmanager = {
        enable = true;
        environmentFile = config.sops.templates."alertmanager.env".path;
        configuration = {
          route = {
            receiver = "discord-notifications";
            group_by = ["alertgroup" "job"];
            group_wait = "30s";
            group_interval = "5m";
            repeat_interval = "12h";
          };
          receivers = [
            {
              name = "discord-notifications";
              discord_configs = [
                {
                  # envsubst-substituted from environmentFile above at
                  # service start (nixpkgs
                  # services.prometheus.alertmanager's `environmentFile`
                  # option) -- not Nix string interpolation; no `${}`
                  # here.
                  webhook_url = "$DISCORD_WEBHOOK_URL";
                }
              ];
            }
          ];
        };
      };
    };

    # docs/MIGRATION.md RAM notes / piece 0.1 "every service gets a
    # systemd MemoryMax derived from the audit": values below are the
    # piece 0.6 capacity audit's measured steady-state figures
    # (docs/MIGRATION.md), superseding the chart's own limits
    # (k8s-manifests monitoring/values.yaml `*.spec.resources.limits.memory`)
    # that this module started from.
    systemd.services = {
      victoriametrics.serviceConfig.MemoryMax = "640M";
      victorialogs.serviceConfig.MemoryMax = "448M";
      grafana = {
        # nixpkgs' services.grafana has no `environmentFile` option
        # (unlike alertmanager above), so this is wired directly onto the
        # systemd unit. Grafana runs as a fixed named user (`grafana`, not
        # DynamicUser), matching modules/nixos/pocket-id.nix's
        # `caddy.env`-style convention of setting the sops template's
        # `owner` when the service has one.
        serviceConfig = {
          MemoryMax = "320M";
          EnvironmentFile = config.sops.templates."grafana.env".path;
        };
      };
      "vmalert-default".serviceConfig.MemoryMax = "128M";
      alertmanager.serviceConfig.MemoryMax = "96M";
    };

    sops = {
      secrets = {
        "grafana/oauth-client-secret" = {};
        # Read directly by the Grafana process (its `$__file{}` provider,
        # not systemd's EnvironmentFile), so -- unlike
        # alertmanager/discord-webhook below -- this needs an explicit
        # owner: the default sops-nix mode (0400, root-owned) would
        # otherwise be unreadable by the `grafana` user.
        "grafana/secret-key" = {owner = "grafana";};
        "alertmanager/discord-webhook" = {};
      };
      templates = {
        "grafana.env" = {
          owner = "grafana";
          content = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder."grafana/oauth-client-secret"}\n";
        };
        # No owner override: alertmanager runs with DynamicUser (nixpkgs
        # module default), same as modules/nixos/netbird-server/default.nix's
        # `netbird-relay.env` template -- EnvironmentFile is read by
        # systemd (PID 1, root) before the unit's dynamic user is
        # allocated, so the sops-nix default owner (root) is sufficient.
        "alertmanager.env".content = "DISCORD_WEBHOOK_URL=${config.sops.placeholder."alertmanager/discord-webhook"}\n";
      };
    };

    # docs/MIGRATION.md piece 6.1 log shipping (mechanism chosen and
    # documented in modules/hosts/legion/default.nix, where the fleet-wide
    # `services.journald.upload` client side lives): VictoriaLogs' journald
    # ingestion route is `/insert/journald/upload` (confirmed against the
    # pinned victorialogs 1.51.0 binary's embedded route strings), and
    # systemd-journal-upload always appends `/upload` to its configured
    # URL itself -- no server-side config needed here beyond VictoriaLogs
    # already listening on vlPort.
  };
}
