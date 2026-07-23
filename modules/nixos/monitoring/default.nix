_: {
  # Monitoring composition module for legion-node3 (VictoriaMetrics,
  # VictoriaLogs, Grafana, vmalert, Alertmanager). Local composition
  # module (DESIGN.md Service Ownership): several first-party modules
  # configured as one service boundary. Imported only for the inventory
  # node placing `monitoring` (modules/hosts/legion/default.nix,
  # legion-node3 today, same optional-import pattern as
  # modules/nixos/blocky.nix). Fleet-wide bits this module depends on
  # (node_exporter, journald log shipping to this node's VictoriaLogs)
  # live in modules/hosts/legion/default.nix's legionConfiguration
  # instead -- they're not "placed" services owned by a single inventory
  # entry.
  #
  # Reset allowed: all state below is node-local disposable storage under
  # /var/lib (systemd's StateDirectory mechanism,
  # services.victoriametrics/victorialogs have no option to point
  # elsewhere) -- no Hetzner Volume, no backupSet, matching the
  # `monitoring` inventory entry (modules/hosts/legion/_service-inventory.nix,
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
    node2 = "172.17.0.2"; # NetBird server metrics, Blocky metrics
    node4 = "172.17.0.4"; # H@H (hath-rust) metrics
    legionPrivateIPs = [
      "172.17.0.1"
      "172.17.0.2"
      "172.17.0.3"
      "172.17.0.4"
    ];

    vmPort = 8428; # services.victoriametrics default listenAddress
    vlPort = 9428; # services.victorialogs default listenAddress

    # blackbox_exporter listen port. Kept at the nixpkgs module default
    # (services.prometheus.exporters.blackbox.port, 9115); named here so
    # the loopback scrape target and the exporter enable-block below agree
    # on one value. The exporter binds loopback only (listenAddress
    # "127.0.0.1" below): VictoriaMetrics scrapes it on this same node
    # (node3), so it needs no private- or public-scope firewall opening at
    # all.
    blackboxPort = 9115;

    # blackbox_exporter probe-module definitions
    # (docs/adr/0003-probe-service-health-from-inside-the-private-network.md).
    # Rendered to a store-path YAML file via pkgs.formats.yaml so the
    # nixpkgs module's build-time `blackbox_exporter --config.check`
    # (services.prometheus.exporters.blackbox.enableConfigCheck, default
    # on) sees a real store path and no store-copy warning fires.
    # preferred_ip_protocol "ip4" on both modules: every probe target is an
    # IPv4 literal on the Legion private network, and blackbox otherwise
    # defaults to attempting ip6 first.
    blackboxConfig = (pkgs.formats.yaml {}).generate "blackbox-exporter.yml" {
      modules = {
        # http_2xx: default valid_status_codes (the whole 2xx range) is
        # left unset because every HTTP target below answers in 2xx on the
        # exact path it is probed at -- verified per target against the
        # nixpkgs-pinned sources:
        #   - pocket-id  /healthz -> 204 No Content (pocket-id backend
        #     internal/controller/healthz_controller.go
        #     `c.Status(http.StatusNoContent)`; 204 is inside 2xx).
        #   - actual     /health  -> 200 {"status":"UP"} (actual
        #     sync-server src/app.ts `res.status(200).json(...)`).
        #   - attic      /        -> 200 HTML placeholder (attic-server
        #     server/src/api/mod.rs root route returns `Html<..>`, a 200).
        http_2xx = {
          prober = "http";
          timeout = "5s";
          http.preferred_ip_protocol = "ip4";
        };
        # tcp_connect: pure TCP-handshake reachability, used for
        # netbird-server's :80. That port multiplexes gRPC + the management
        # HTTP API (modules/nixos/netbird-server/default.nix
        # `listenAddress: ":80"`), so a plain HTTP/1.1 GET is not a reliable
        # liveness check; a completed TCP connect is exactly the "answers on
        # its backend port" signal docs/adr/0003 calls for. (The server's
        # dedicated `healthcheckAddress: ":9000"` is deliberately not used:
        # :9000 is not declared in modules/hosts/legion/_service-inventory.nix,
        # so probing it would need the firewall change docs/adr/0003 avoids;
        # :80 already is declared, see the scrape job below.)
        tcp_connect = {
          prober = "tcp";
          timeout = "5s";
          tcp.preferred_ip_protocol = "ip4";
        };
      };
    };

    # retentionPeriod "1" means one month (VictoriaMetrics/VictoriaLogs
    # count an unsuffixed retentionPeriod in months). Neither
    # nixpkgs-pinned module accepts a bare "1" typed differently, so both
    # get the identical string.
    retentionPeriod = "1";

    dashboardsDir = pkgs.linkFarm "grafana-dashboards" [
      {
        # CrowdSec is scraped at :6060/metrics (mirrored below); this is
        # the matching Grafana dashboard for it. Only populated once
        # `edge.crowdsec.enable` is true, but the board is carried
        # regardless.
        name = "crowdsec.json";
        path = ./crowdsec-dashboard.json;
      }
      {
        # "Node Exporter Full" (grafana.com dashboard #1860), vendored as a
        # store file so nothing is fetched at build time (pure-eval CI /
        # offline build). The vendored revision already uses a
        # `${ds_prometheus}` datasource *template variable* (type
        # "datasource", query "prometheus") -- same file-provisioning-safe
        # pattern as crowdsec-dashboard.json's `${datasource}` var -- so it
        # resolves against the VictoriaMetrics (prometheus-type) datasource
        # with no interactive import step. Its `$job`/`$nodename`/`$node`
        # variables populate from node_uname_info, whose labels match our
        # `job="node"` scrape and `instance="<ip>:9100"` targets.
        name = "node-exporter-full.json";
        path = ./node-exporter-full.json;
      }
      {
        # Hand-authored fleet landing board (per-node CPU/mem/disk, scrape
        # up/down, failed systemd units, backend probe failures). References
        # the VictoriaMetrics datasource by its fixed uid ("victoriametrics",
        # set below) rather than a datasource variable, since it targets that
        # one datasource directly.
        name = "fleet-overview.json";
        path = ./fleet-overview.json;
      }
      # --- Per-service boards (Part D). Each targets one scrape job below.
      # Hand-authored boards reference the VictoriaMetrics datasource by its
      # fixed uid ("victoriametrics") like fleet-overview.json; the two
      # vendored boards resolve it via a `datasource`-type template variable
      # (query "prometheus", current "Default") that binds to the same
      # isDefault datasource, the file-provisioning-safe pattern
      # node-exporter-full.json / crowdsec-dashboard.json already use. All
      # PromQL was checked against the nixpkgs-pinned service sources so
      # panels reference real exposed metric names.
      {
        # Hand-authored board for the edge Caddy reverse proxy (job "caddy",
        # 172.17.0.1:2020). Metric names verified against caddy v2.11.4
        # (modules/caddyhttp/metrics.go + reverseproxy/metrics.go): request
        # rate/latency percentiles from caddy_http_request_duration_seconds_*,
        # status-code breakdown from that histogram's _count series (which
        # carries `code`; caddy_http_requests_total does not),
        # caddy_reverse_proxy_upstreams_healthy, response bytes, Go runtime.
        name = "caddy.json";
        path = ./caddy.json;
      }
      {
        # Vendored "Blocky" board (grafana.com #13768 revision 8), whose
        # metric names match blocky 0.33.0 exactly (verified against
        # resolver/metrics_resolver.go + metrics/metrics_event_publisher.go:
        # blocky_query_total, blocky_response_total, blocky_cache_entries,
        # blocky_denylist_cache_entries, blocky_request_duration_seconds, ...).
        # Adapted for file provisioning: __inputs emptied, the VAR_BLOCKY_URL
        # input placeholder resolved to its upstream default, uid pinned. Its
        # $job/$instance variables populate from blocky_build_info, matching
        # our job "blocky" scrape (172.17.0.2:8000).
        name = "blocky.json";
        path = ./blocky.json;
      }
      {
        # Hand-authored board for the NetBird management server (job
        # "netbird-server", 172.17.0.2:9090). Instruments verified against
        # netbird v0.74.3 (management/server/telemetry/{grpc,http_api}_
        # metrics.go). Those are OpenTelemetry instruments exported by the
        # otel prometheus exporter v0.64.0 with defaults, so counter names may
        # gain `_total` and the *.duration.ms histograms may gain a
        # `_milliseconds` unit suffix -- not recoverable from source without a
        # live scrape -- so the board's selectors match __name__ with the
        # verified base name plus an optional suffix (PromQL regexes are
        # anchored, so they can't collide). No peer/account gauges exist here:
        # those live in a PostHog usage payload (metrics/selfhosted.go), not
        # /metrics.
        name = "netbird-server.json";
        path = ./netbird-server.json;
      }
      {
        # Hand-authored board for the H@H client (hath-rust, job "hath",
        # 172.17.0.4:8888/metrics over https). Metric names verified against
        # hath-rust v1.17.0 (src/metrics.rs): a prometheus-client
        # Registry::with_prefix("hath"), so counters carry `_total` and
        # register_with_unit(Bytes/Seconds) appends `_bytes`/`_seconds`
        # (hath_cache_sent_total, hath_cache_sent_size_bytes_total,
        # hath_cache_sent_duration_seconds_*, hath_connections,
        # hath_cache_size_bytes/_capacity_bytes/_count, hath_download_*,
        # hath_uptime_seconds_total).
        name = "hath.json";
        path = ./hath.json;
      }
      {
        # Vendored "Prometheus Blackbox Exporter" board (grafana.com #7587
        # revision 3). Covers our blackbox-http / blackbox-tcp jobs (the
        # `$target` variable enumerates label_values(probe_success, instance),
        # i.e. each probed URL/host:port). Adapted for file provisioning:
        # __inputs emptied and every datasource ref repointed onto a
        # `datasource`-type template variable (this old schemaVersion-16 board
        # shipped with a per-panel ${DS_...} input instead). SSL-expiry and
        # HTTP-version panels read empty by design -- our probes are private
        # backends over plain http/tcp (docs/adr/0003), no TLS -- kept rather
        # than deleted so the board stays a faithful copy of the upstream.
        name = "blackbox.json";
        path = ./blackbox.json;
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
            # section (default enabled, port 6060). Only populated once
            # `edge.crowdsec.enable` is true -- until then this target
            # legitimately reads down.
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
            # `metricsPort: 9090` in its rendered config.yaml. The relay
            # has no metrics endpoint, so none is scraped here either.
            job_name = "netbird-server";
            static_configs = [
              {
                targets = ["${node2}:9090"];
                labels.type = "netbird";
              }
            ];
          }
          {
            # modules/nixos/blocky.nix: runs on legion-node2 -- this node
            # (node3) scrapes it cross-node over the private network (Blocky
            # binds :8000 on all interfaces, enp7s0 is a trusted
            # interface, same reachability pattern as every other
            # cross-node backend in this module). No explicit prometheus
            # section on Blocky's side (metrics ride the existing
            # `ports.http` listener, per that module's own comment).
            job_name = "blocky";
            static_configs = [
              {
                targets = ["${node2}:8000"];
                labels.type = "dns";
              }
            ];
          }
          {
            # H@H (hath-rust) on legion-node4
            # (modules/nixos/hath.nix, runs with `--enable-metrics`).
            # Verified against the nixpkgs-pinned hath-rust 1.17.0 source
            # (github.com/james58899/hath-rust v1.17.0): `--enable-metrics`
            # registers a single `/metrics` route (src/server/mod.rs
            # `router.route("/metrics", get(route::metrics))`) on the *same*
            # listener as the H@H client itself -- there is no separate
            # metrics port. That listener is the `--port 8888` socket
            # (src/main.rs `bind(SocketAddr::from(([0,0,0,0], port)))`), so
            # the endpoint is 172.17.0.4:8888/metrics -- the port already
            # opened public-scope for H@H
            # (modules/hosts/legion/_service-inventory.nix hath.firewall +
            # modules/hosts/legion/default.nix `++ [8888]`), reachable
            # cross-node over the trusted private interface (enp7s0) like
            # every other backend here. No new firewall entry needed: it's
            # the existing H@H port, not a separate metrics port.
            #
            # scheme = "https" (not the default http): that same listener is
            # TLS-wrapped (src/server/mod.rs wraps every connection in a
            # `TlsAcceptor`), so /metrics is only served over TLS. The cert
            # is the H@H-network-issued client cert fetched at startup from
            # the H@H RPC server (src/main.rs `client.get_cert()`), issued
            # for the client's hath.network identity -- it has no SAN for
            # 172.17.0.4, so `tls_config.insecure_skip_verify` is required
            # (this is a private-interface scrape, transport trust is the
            # enp7s0 boundary, not this cert). Path left at the /metrics
            # default (matches the route above).
            job_name = "hath";
            scheme = "https";
            tls_config.insecure_skip_verify = true;
            static_configs = [
              {
                targets = ["${node4}:8888"];
                labels.type = "hath";
              }
            ];
          }
          # --- Synthetic backend health probes via blackbox_exporter ---
          # (docs/adr/0003-probe-service-health-from-inside-the-private-network.md).
          # Standard blackbox relabel: the probe target starts life in
          # __address__, is copied into the ?target= query param
          # (__param_target), preserved verbatim as the `instance` label,
          # and then __address__ is rewritten to the blackbox exporter's own
          # loopback socket so VictoriaMetrics actually scrapes the
          # exporter's /probe handler (which in turn probes ?target=).
          #
          # Every target port below is already declared private-scope in
          # modules/hosts/legion/_service-inventory.nix -- pocket-id :1411
          # and netbird-server :80 (legion-node2), actual-budget :5006 and
          # attic :8080 (legion-node4) -- reachable cross-node over the
          # trusted enp7s0 interface exactly like every metrics scrape
          # above. So NO new host firewall opening and NO Hetzner Cloud
          # Firewall rule is added for probing (docs/adr/0003 Consequences).
          {
            job_name = "blackbox-http";
            metrics_path = "/probe";
            params.module = ["http_2xx"];
            # Full URLs (scheme + health path): the http prober probes the
            # ?target= value verbatim, so scheme and path must be present.
            # Paths chosen per target for a clean 2xx (see blackboxConfig in
            # the `let` block for the per-target status-code verification).
            # Split into two target blocks purely to carry a per-target `tier`
            # label, which BlackboxProbeDown maps to the alert severity below.
            static_configs = [
              {
                # pocket-id is the fleet SSO provider (auth.jeiang.dev): a
                # down backend locks users out of every OAuth-gated service,
                # so its probe failure is `critical` (pages), matching the
                # netbird-server VPN target in the tcp job.
                targets = ["http://${node2}:1411/healthz"];
                labels = {
                  type = "probe";
                  tier = "critical";
                };
              }
              {
                # actual-budget (budget) and attic (Nix binary cache) are
                # important but not auth-critical -- a stale cache or an
                # unreachable budget app degrades, it doesn't lock the fleet
                # out -- so these stay `warning`, same tier as
                # SystemdUnitFailed.
                targets = [
                  "http://${node4}:5006/health"
                  "http://${node4}:8080/"
                ];
                labels = {
                  type = "probe";
                  tier = "warning";
                };
              }
            ];
            relabel_configs = [
              {
                source_labels = ["__address__"];
                target_label = "__param_target";
              }
              {
                source_labels = ["__param_target"];
                target_label = "instance";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:${toString blackboxPort}";
              }
            ];
          }
          {
            job_name = "blackbox-tcp";
            metrics_path = "/probe";
            params.module = ["tcp_connect"];
            static_configs = [
              {
                # host:port, no scheme, for the tcp prober. netbird-server
                # :80 multiplexes gRPC + management HTTP, so a TCP connect
                # is the robust liveness signal here (see blackboxConfig).
                # `tier = "critical"`: netbird is the fleet VPN -- a down
                # management/signal server breaks mesh connectivity, so this
                # pages, same as the pocket-id SSO target in the http job.
                targets = ["${node2}:80"];
                labels = {
                  type = "probe";
                  tier = "critical";
                };
              }
            ];
            relabel_configs = [
              {
                source_labels = ["__address__"];
                target_label = "__param_target";
              }
              {
                source_labels = ["__param_target"];
                target_label = "instance";
              }
              {
                target_label = "__address__";
                replacement = "127.0.0.1:${toString blackboxPort}";
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
            http_addr = "0.0.0.0";
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
          # Pocket ID generic OAuth. client_secret is deliberately absent
          # here: delivered via
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
        # filters on `query: "prometheus"`) working without changes.
        # VictoriaLogs has no
        # built-in Grafana datasource type, so its dedicated community
        # plugin is still needed (declarativePlugins below).
        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "VictoriaMetrics";
              type = "prometheus";
              # Stable, hand-picked uid so file-provisioned dashboards can
              # reference this datasource deterministically (the
              # fleet-overview.json panels point at `uid: victoriametrics`)
              # instead of relying on Grafana's auto-generated random uid.
              # Does not affect crowdsec.json / node-exporter-full.json,
              # which resolve via a `datasource`-type template variable, not
              # a fixed uid.
              uid = "victoriametrics";
              url = "http://127.0.0.1:${toString vmPort}";
              isDefault = true;
            }
            {
              name = "VictoriaLogs";
              type = "victoriametrics-logs-datasource";
              # Stable uid for the same reason as VictoriaMetrics above, so
              # future log dashboards (Part E) can reference it by name.
              uid = "victorialogs";
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
      # same node). There is no concrete Kubernetes-era rule set that
      # applies to a single host-native node, so this starts with the
      # minimal meaningful set below (instance/service down, disk
      # pressure, memory pressure); expanding it is a gap and upgrade path
      # for future work.
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
              {
                # Emitted by node_exporter's systemd collector, enabled
                # fleet-wide in modules/hosts/legion/default.nix
                # (enabledCollectors = ["systemd"], scoped to a first-party
                # unit-include allowlist). The collector publishes one
                # `node_systemd_unit_state{name,state,type}` series per
                # (unit, state) with value 1 for the unit's current state
                # (confirmed against the pinned node_exporter 1.12.0), so a
                # failed unit shows up as `state="failed"` == 1. `$labels.name`
                # is the collector's unit-name label (e.g. "hath.service").
                alert = "SystemdUnitFailed";
                expr = ''node_systemd_unit_state{state="failed"} == 1'';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "systemd unit {{ $labels.name }} failed on {{ $labels.instance }}";
                  description = "{{ $labels.name }} on {{ $labels.instance }} has been in the failed state for 5 minutes.";
                };
              }
              {
                # Backend liveness from blackbox_exporter's probes
                # (docs/adr/0003-probe-service-health-from-inside-the-private-network.md;
                # blackbox-http/blackbox-tcp scrape jobs above). probe_success
                # is 0 when a probed backend does not answer on its private
                # port. Severity is per-target, not fleet-uniform: the
                # `tier` label set on each probe target in the scrape jobs
                # above ("critical" for the pocket-id SSO and netbird VPN
                # backends, "warning" for the actual/attic backends) is
                # carried onto the alert series and mapped straight to
                # `severity` via the vmalert label template below. Distinct
                # from the critical fleet-wide TargetDown (up == 0), which
                # fires when a scrape target vanishes entirely -- note a down
                # backend here still leaves the blackbox exporter's own scrape
                # up, so TargetDown would NOT catch it. The 5m `for` debounces
                # service restarts. `$labels.instance` is the probed
                # URL/host:port (set by the jobs' relabel_configs);
                # `$labels.job` is blackbox-http or blackbox-tcp.
                alert = "BlackboxProbeDown";
                expr = "probe_success == 0";
                for = "5m";
                labels.severity = "{{ $labels.tier }}";
                annotations = {
                  summary = "Probe failing for {{ $labels.instance }}";
                  description = "The {{ $labels.job }} probe for {{ $labels.instance }} has been failing for 5 minutes.";
                };
              }
            ];
          }
        ];
      };

      # blackbox_exporter: synthetic liveness probes of first-party service
      # backends over the Legion private network
      # (docs/adr/0003-probe-service-health-from-inside-the-private-network.md).
      # Scraped by this node's own VictoriaMetrics via the blackbox-http /
      # blackbox-tcp jobs in prometheusConfig.scrape_configs above; probe
      # modules defined in blackboxConfig (the `let` block).
      prometheus.exporters.blackbox = {
        enable = true;
        # Set explicitly to the module default so the scrape target's
        # 127.0.0.1:${blackboxPort} above and the exporter cannot drift.
        port = blackboxPort;
        # Loopback-only: the sole scraper is VictoriaMetrics on this same
        # node (node3), so the exporter needs no firewall surface at all --
        # stricter than the cross-node backends this module scrapes, which
        # at least ride enp7s0. Also keeps the exporter's /probe handler
        # (an SSRF-shaped `GET /probe?target=` primitive) off the network.
        listenAddress = "127.0.0.1";
        configFile = blackboxConfig;
      };

      # Alertmanager: Discord webhook, with routing/grouping configured
      # below.
      prometheus.alertmanager = {
        enable = true;
        environmentFile = config.sops.templates."alertmanager.env".path;
        checkConfig = false;
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

    # Values below are measured steady-state figures.
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
      # blackbox_exporter is tiny -- a handful of concurrent probes on the
      # scrape interval -- so 32M is comfortable headroom. Unit name is the
      # nixpkgs exporter-wrapper convention `prometheus-<name>-exporter`
      # (nixpkgs .../monitoring/prometheus/exporters.nix
      # `systemd.services."prometheus-${name}-exporter"`).
      prometheus-blackbox-exporter.serviceConfig.MemoryMax = "32M";
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

    # Log shipping (mechanism chosen and documented in
    # modules/hosts/legion/default.nix, where the fleet-wide
    # `services.journald.upload` client side lives): VictoriaLogs' journald
    # ingestion route is `/insert/journald/upload` (confirmed against the
    # pinned victorialogs 1.51.0 binary's embedded route strings), and
    # systemd-journal-upload always appends `/upload` to its configured
    # URL itself -- no server-side config needed here beyond VictoriaLogs
    # already listening on vlPort.
  };
}
