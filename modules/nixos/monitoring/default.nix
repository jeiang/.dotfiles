{self, ...}: {
  flake.nixosModules.monitoring = {
    config,
    pkgs,
    ...
  }: let
    node1 = self.lib.legionNodes.legion-node1.privateIPv4;
    node2 = self.lib.legionNodes.legion-node2.privateIPv4;
    node4 = self.lib.legionNodes.legion-node4.privateIPv4;

    sopsFile = ./secrets.yaml;
    legionPrivateIPs = map (node: node.privateIPv4) (builtins.attrValues self.lib.legionNodes);

    ports = self.lib.ports;
    vmPort = ports.legion-node3.victoria-metrics;
    vlPort = ports.legion-node3.victoria-logs;

    blackboxPort = 9115;

    # blackbox otherwise attempts ip6 first; every probe target is an IPv4
    # literal on the private network.
    blackboxConfig = (pkgs.formats.yaml {}).generate "blackbox-exporter.yml" {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "5s";
          http.preferred_ip_protocol = "ip4";
        };
        tcp_connect = {
          prober = "tcp";
          timeout = "5s";
          tcp.preferred_ip_protocol = "ip4";
        };
      };
    };

    # "1" = one month; unsuffixed retentionPeriod values count months.
    retentionPeriod = "1";

    dashboardsDir = pkgs.linkFarm "grafana-dashboards" [
      {
        name = "crowdsec.json";
        path = ./crowdsec-dashboard.json;
      }
      {
        # Vendored grafana.com dashboard #1860.
        name = "node-exporter-full.json";
        path = ./node-exporter-full.json;
      }
      {
        name = "fleet-overview.json";
        path = ./fleet-overview.json;
      }
      {
        name = "caddy.json";
        path = ./caddy.json;
      }
      {
        # Vendored grafana.com dashboard #13768 rev 8, adapted for file
        # provisioning.
        name = "blocky.json";
        path = ./blocky.json;
      }
      {
        name = "netbird-server.json";
        path = ./netbird-server.json;
      }
      {
        name = "hath.json";
        path = ./hath.json;
      }
      {
        name = "garret.json";
        path = ./garret.json;
      }
      {
        # Vendored grafana.com dashboard #7587 rev 3, adapted for file
        # provisioning.
        name = "blackbox.json";
        path = ./blackbox.json;
      }
      {
        name = "logs.json";
        path = ./logs.json;
      }
    ];
  in {
    services = {
      victoriametrics = {
        enable = true;
        inherit retentionPeriod;
        prometheusConfig.scrape_configs = [
          {
            job_name = "node";
            static_configs = [
              {
                targets = map (ip: "${ip}:9100") legionPrivateIPs;
                labels.type = "node";
              }
              {
                # artemis's NetBird peer IP (mesh DNS doesn't resolve on
                # Legion nodes); changes if artemis is ever re-enrolled.
                targets = ["100.89.148.91:9100"];
                labels.type = "node";
              }
            ];
          }
          {
            job_name = "caddy";
            static_configs = [
              {
                targets = ["${node1}:2020"];
                labels.type = "edge";
              }
            ];
          }
          {
            # Only populated once edge.crowdsec.enable is true -- until then
            # this target legitimately reads down.
            job_name = "crowdsec";
            static_configs = [
              {
                targets = ["${node1}:6060"];
                labels.type = "edge";
              }
            ];
          }
          {
            # The relay exposes no metrics endpoint, so none is scraped.
            job_name = "netbird-server";
            static_configs = [
              {
                targets = ["${node2}:${toString ports.legion-node2.netbird-server-metrics}"];
                labels.type = "netbird";
              }
            ];
          }
          {
            job_name = "blocky";
            static_configs = [
              {
                targets = ["${node2}:8000"];
                labels.type = "dns";
              }
            ];
          }
          {
            # H@H serves /metrics on the same TLS-wrapped listener as the
            # client itself; its hath.network cert has no SAN for this IP,
            # hence insecure_skip_verify (transport trust is enp7s0).
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
          {
            job_name = "garret";
            static_configs = [
              {
                targets = ["${node4}:${toString ports.legion-node4.garret-pusher-metrics}"];
                labels = {
                  type = "cache";
                  component = "pusher";
                };
              }
              {
                targets = ["${node4}:${toString ports.legion-node4.garret-puller-metrics}"];
                labels = {
                  type = "cache";
                  component = "puller";
                };
              }
            ];
          }
          {
            job_name = "blackbox-http";
            metrics_path = "/probe";
            params.module = ["http_2xx"];
            static_configs = [
              {
                targets = ["http://${node2}:${toString ports.legion-node2.pocket-id}/healthz"];
                labels = {
                  type = "probe";
                  tier = "critical";
                };
              }
              {
                targets = ["http://${node4}:${toString ports.legion-node4.actual-budget}/health"];
                labels = {
                  type = "probe";
                  tier = "warning";
                };
              }
              {
                # The Pusher's service port is fully token-gated, so its
                # probe targets the metrics listener's /healthz instead.
                targets = [
                  "http://${node4}:${toString ports.legion-node4.garret-puller}/nix-cache-info"
                  "http://${node4}:${toString ports.legion-node4.garret-pusher-metrics}/healthz"
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
                # :80 multiplexes gRPC + the management HTTP API, so a TCP
                # connect (not a plain GET) is the reliable liveness signal.
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
        extraOptions = ["-retentionPeriod=${retentionPeriod}"];
      };

      grafana = {
        enable = true;
        settings = {
          server = {
            domain = "grafana.jeiang.dev";
            root_url = "https://grafana.jeiang.dev";
            http_addr = "0.0.0.0";
          };
          auth = {
            disable_login_form = true;
            oauth_auto_login = true;
          };
          security = {
            # nixpkgs 26.05 asserts a value is set; $__file{} keeps the
            # secret itself out of the Nix-store-rendered ini.
            secret_key = "$__file{${config.sops.secrets."grafana/secret-key".path}}";
          };
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

        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "VictoriaMetrics";
              type = "prometheus";
              uid = "victoriametrics";
              url = "http://127.0.0.1:${toString vmPort}";
              isDefault = true;
            }
            {
              name = "VictoriaLogs";
              type = "victoriametrics-logs-datasource";
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
                # TargetDown would NOT catch a down backend: the blackbox
                # exporter's own scrape stays up while probe_success is 0.
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

      prometheus.exporters.blackbox = {
        enable = true;
        port = blackboxPort;
        # Loopback-only: keeps the /probe handler (an SSRF-shaped
        # `GET /probe?target=` primitive) off the network.
        listenAddress = "127.0.0.1";
        configFile = blackboxConfig;
      };

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
                  # envsubst-substituted from environmentFile at service
                  # start -- not Nix interpolation; no `${}` here.
                  webhook_url = "$DISCORD_WEBHOOK_URL";
                }
              ];
            }
          ];
        };
      };
    };

    systemd.services = {
      # Unordered, an activation restarting both races: journal-upload
      # crash-loops before VictoriaLogs is up and deploy-rs rolls the whole
      # deploy back (observed 2026-08-17).
      systemd-journal-upload = {
        after = ["victorialogs.service"];
        wants = ["victorialogs.service"];
      };
      victoriametrics.serviceConfig.MemoryMax = "640M";
      victorialogs.serviceConfig.MemoryMax = "448M";
      grafana = {
        # services.grafana has no environmentFile option, so this is wired
        # directly onto the systemd unit.
        serviceConfig = {
          MemoryMax = "320M";
          EnvironmentFile = config.sops.templates."grafana.env".path;
        };
      };
      "vmalert-default".serviceConfig.MemoryMax = "128M";
      alertmanager.serviceConfig.MemoryMax = "96M";
      prometheus-blackbox-exporter.serviceConfig.MemoryMax = "32M";
    };

    sops = {
      secrets = {
        "grafana/oauth-client-secret" = {inherit sopsFile;};
        "grafana/secret-key" = {
          inherit sopsFile;
          owner = "grafana";
          restartUnits = ["grafana.service"];
        };
        "alertmanager/discord-webhook" = {inherit sopsFile;};
      };
      templates = {
        "grafana.env" = {
          owner = "grafana";
          restartUnits = ["grafana.service"];
          content = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder."grafana/oauth-client-secret"}\n";
        };
        "alertmanager.env" = {
          restartUnits = ["alertmanager.service"];
          content = "DISCORD_WEBHOOK_URL=${config.sops.placeholder."alertmanager/discord-webhook"}\n";
        };
      };
    };
  };
}
