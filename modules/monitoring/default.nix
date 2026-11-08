{
  self,
  config,
  ...
}: let
  vmPort = 8428;
  vlPort = 9428;
  vtPort = 10428;
  grafanaPort = 3000;

  legionServices = config.legion.services;
in {
  flake.lib.grafanaHostname = "grafana.jeiang.dev";

  legion.services.monitoring = {
    node = "zantark";
    module = "monitoring";
    units = ["grafana" "victoriametrics" "victorialogs" "victoriatraces" "vmalert-default" "alertmanager" "prometheus-blackbox-exporter"];
    ports = {
      grafana = grafanaPort;
      victoria-logs = vlPort;
      victoria-traces = vtPort;
    };
  };

  nixos.modules.artemis.services.prometheus.exporters.smartctl.enable = true;

  nixos.modules.monitoring = {
    config,
    lib,
    pkgs,
    ...
  }: let
    sopsFile = ./secrets.yaml;
    serviceAddress = self.lib.serviceAddress config.networking.hostName;
    nodeExporterPort = toString config.services.prometheus.exporters.node.port;
    artemisExporters = self.nixosConfigurations.artemis.config.services.prometheus.exporters;
    # A node outside the private network is scraped over the mesh and drops out until it has a peer entry.
    legionNodeAddresses = builtins.filter (a: a != null) (map (self.lib.legionAddress config.networking.hostName) (builtins.attrNames self.lib.legionNodes));

    # Where this node reaches a service port; empty while its node is mesh-only without a peer entry.
    at = svc: key: path: let
      a = serviceAddress svc;
    in
      lib.optional (a != null) "${a}:${toString legionServices.${svc}.ports.${key}}${path}";

    http = map (t: "http://${t}");

    scrape = job_name: type: targets: {
      inherit job_name;
      static_configs = [
        {
          inherit targets;
          labels.type = type;
        }
      ];
    };

    # Each probe target becomes the exporter's ?target= and the instance label.
    probe = job_name: module: groups: {
      inherit job_name;
      metrics_path = "/probe";
      params.module = [module];
      static_configs =
        lib.mapAttrsToList (tier: targets: {
          inherit targets;
          labels = {
            type = "probe";
            inherit tier;
          };
        })
        groups;
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
          replacement = "127.0.0.1:${toString config.services.prometheus.exporters.blackbox.port}";
        }
      ];
    };

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
        dns = {
          prober = "dns";
          timeout = "5s";
          dns = {
            query_name = self.lib.netbirdDomain;
            query_type = "A";
            valid_rcodes = ["NOERROR"];
            preferred_ip_protocol = "ip4";
          };
        };
      };
    };

    # "1" = one month; unsuffixed retentionPeriod values count months.
    retentionPeriod = "1";
  in {
    services = {
      victoriametrics = {
        enable = true;
        listenAddress = ":${toString vmPort}";
        inherit retentionPeriod;
        prometheusConfig.scrape_configs =
          [
            (scrape "node" "node" (map (ip: "${ip}:${nodeExporterPort}") legionNodeAddresses ++ ["${self.lib.netbirdPeers.artemis}:${toString artemisExporters.node.port}"]))
            (scrape "smartctl" "node" ["${self.lib.netbirdPeers.artemis}:${toString artemisExporters.smartctl.port}"])
            (scrape "caddy" "edge" (at "caddy" "metrics" ""))
            (scrape "crowdsec" "edge" (at "crowdsec" "metrics" ""))
            (scrape "netbird-server" "netbird" (at "netbird-server" "metrics" ""))
            (scrape "netbird-relay" "netbird" (at "netbird-relay" "metrics" ""))
          ]
          ++ map (service: scrape service "netbird" (at service "health" "")) self.lib.netbirdProxyServices
          ++ [
            (scrape "blocky" "dns" (at "blocky" "http" "" ++ at "blocky-ricklent" "http" ""))
            # H@H serves /metrics on the same TLS-wrapped listener as the client
            # itself; its hath.network cert has no SAN for this IP, hence
            # insecure_skip_verify (transport trust is the private network).
            (scrape "hath" "hath" (at "hath" "app" "")
              // {
                scheme = "https";
                tls_config.insecure_skip_verify = true;
              })
            {
              job_name = "garret";
              static_configs = map (component: {
                targets = at "garret" "${component}-metrics" "";
                labels = {
                  type = "cache";
                  inherit component;
                };
              }) ["pusher" "puller"];
            }
            (scrape "gatus" "probe" (at "gatus" "app" ""))
            (probe "blackbox-http" "http_2xx" {
              critical = http (at "pocket-id" "app" "/healthz");
              # /ready/deep reads a byte of a real NAR through a presigned URL,
              # so revoked S3 credentials or an S4 outage fail it; the Pusher's
              # service port is fully token-gated, so its probe targets the
              # metrics listener's /healthz instead.
              warning = http (at "ntfy" "app" "/v1/health"
                ++ at "garret" "puller" "/ready/deep"
                ++ at "garret" "pusher-metrics" "/healthz"
                ++ at "netbird-relay" "health" "/health"
                ++ lib.concatMap (service: at service "health" "/healthz") self.lib.netbirdProxyServices);
            })
            # :80 multiplexes gRPC + the management HTTP API, so a TCP connect
            # (not a plain GET) is the reliable liveness signal.
            (probe "blackbox-tcp" "tcp_connect" {critical = at "netbird-server" "http" "";})
            (probe "blackbox-dns" "dns" {warning = at "blocky" "dns" "";})
          ];
      };

      victorialogs = {
        enable = true;
        listenAddress = ":${toString vlPort}";
        extraOptions = ["-retentionPeriod=${retentionPeriod}"];
      };

      # OTLP over HTTP at /insert/opentelemetry/v1/traces.
      victoriatraces = {
        enable = true;
        listenAddress = ":${toString vtPort}";
        inherit retentionPeriod;
        # A chatty sender must not fill the root disk the metrics and logs share.
        extraOptions = ["-retention.maxDiskSpaceUsageBytes=5GiB"];
      };

      grafana = {
        enable = true;
        settings = {
          server = {
            domain = self.lib.grafanaHostname;
            root_url = "https://${self.lib.grafanaHostname}";
            http_addr = "0.0.0.0";
            http_port = grafanaPort;
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
            auth_url = "${self.lib.pocketIdUrl}/authorize";
            token_url = "${self.lib.pocketIdUrl}/api/oidc/token";
            api_url = "${self.lib.pocketIdUrl}/api/oidc/userinfo";
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
            {
              name = "VictoriaTraces";
              type = "jaeger";
              uid = "victoriatraces";
              url = "http://127.0.0.1:${toString vtPort}/select/jaeger";
            }
          ];
          dashboards.settings.providers = [
            {
              name = "default";
              options.path = ./dashboards;
            }
          ];
        };
        declarativePlugins = with pkgs.grafanaPlugins; [prometheus victoriametrics-logs-datasource jaeger];
      };

      vmalert.instances.default = {
        enable = true;
        settings = {
          "datasource.url" = "http://127.0.0.1:${toString vmPort}";
          "notifier.url" = ["http://127.0.0.1:${toString config.services.prometheus.alertmanager.port}"];
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
                # artemis's btrfs pool is RAID0 over three NVMe drives; any of these precedes losing it.
                alert = "DiskHealthDegraded";
                expr = "smartctl_device_smart_status != 1 or smartctl_device_critical_warning > 0 or smartctl_device_percentage_used >= 90 or increase(smartctl_device_media_errors[1d]) > 0";
                for = "0m";
                labels.severity = "critical";
                annotations = {
                  summary = "Drive {{ $labels.device }} on {{ $labels.instance }} reports degraded health";
                  description = "SMART on {{ $labels.device }} ({{ $labels.instance }}) shows a failed status, a critical warning, 90% wear, or new media errors.";
                };
              }
              {
                alert = "BtrfsDeviceErrors";
                expr = "increase(node_btrfs_device_errors_total[1h]) > 0";
                for = "0m";
                labels.severity = "critical";
                annotations = {
                  summary = "btrfs device errors on {{ $labels.instance }}";
                  description = "{{ $labels.device }} logged {{ $labels.type }} errors on {{ $labels.instance }} in the last hour.";
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
              {
                alert = "ResticBackupStale";
                # node_systemd_timer_last_trigger_seconds is 0 for a timer
                # that has never fired, which would otherwise satisfy > 36h
                # for a newly added job until its first randomized run.
                expr = ''(time() - node_systemd_timer_last_trigger_seconds{name=~"restic-backups-.*\\.timer"} > 36 * 3600) and node_systemd_timer_last_trigger_seconds{name=~"restic-backups-.*\\.timer"} > 0'';
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "{{ $labels.name }} has not triggered in over 36h on {{ $labels.instance }}";
                  description = "The restic backup timer {{ $labels.name }} on {{ $labels.instance }} last fired more than 36 hours ago.";
                };
              }
              {
                alert = "GatusEndpointDown";
                expr = "gatus_results_endpoint_success == 0";
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Gatus endpoint {{ $labels.name }} failing";
                  description = "The Gatus check {{ $labels.name }} ({{ $labels.group }}) has been failing for 10 minutes.";
                };
              }
              {
                alert = "GarretDegraded";
                expr = "increase(garret_degraded_total[15m]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret puller degraded on {{ $labels.instance }}";
                  description = "garret_degraded_total increased on {{ $labels.instance }} in the last 15 minutes: a DB or presign read failed or timed out.";
                };
              }
              {
                alert = "GarretUploadsFailed";
                expr = "increase(garret_uploads_failed_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret pusher upload failures on {{ $labels.instance }}";
                  description = "garret_uploads_failed_total increased on {{ $labels.instance }} in the last hour.";
                };
              }
              {
                # GC evicts on its next tick once usage passes the high
                # watermark, so staying above it means eviction is stuck.
                alert = "GarretOverHighWatermark";
                expr = "garret_gc_usage_bytes / garret_gc_quota_bytes > ${toString self.lib.garretHighWatermark}";
                for = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret usage above the high watermark on {{ $labels.instance }}";
                  description = "garret bucket usage on {{ $labels.instance }} has been at {{ $value | humanizePercentage }} of quota for 30 minutes without GC bringing it down.";
                };
              }
              {
                alert = "GarretGcCandidatesExhausted";
                expr = "increase(garret_gc_candidates_exhausted_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret GC ran out of eviction candidates on {{ $labels.instance }}";
                  description = "A GC pass on {{ $labels.instance }} stopped above the low watermark: everything left is referenced, pinned, or pushed in the last day. Raise the quota, unpin, or prune.";
                };
              }
              {
                alert = "GarretGcFailed";
                expr = "increase(garret_gc_failures_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret GC {{ $labels.phase }} failed on {{ $labels.instance }}";
                  description = "garret_gc_failures_total{phase=\"{{ $labels.phase }}\"} increased on {{ $labels.instance }} in the last hour.";
                };
              }
              {
                # The series only exists once the Pusher has accepted an
                # upload since it started, hence the absent_over_time arm.
                alert = "GarretNoUploads";
                expr = ''sum(increase(garret_uploads_accepted_total{job="garret"}[7d])) == 0 or absent_over_time(garret_uploads_accepted_total{job="garret"}[7d])'';
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret accepted no uploads in 7 days";
                  description = "garret_uploads_accepted_total has not increased in 7 days: CI pushes are failing or being refused.";
                };
              }
              {
                alert = "GarretJwksRefreshFailed";
                expr = "increase(garret_jwks_refresh_failures_total[1h]) > 1";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret could not refresh the JWKS of {{ $labels.issuer }}";
                  description = "garret failed more than one JWKS refresh for {{ $labels.issuer }} on {{ $labels.instance }} in the last hour. Cached keys keep validating, but a token signed by a key the issuer rotated in is refused until a refresh succeeds.";
                };
              }
              {
                alert = "GarretS3DeleteFailed";
                expr = "increase(garret_s3_delete_failures_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret S3 deletes failing on {{ $labels.instance }}";
                  description = "garret_s3_delete_failures_total increased on {{ $labels.instance }} in the last hour: the blobs are orphans until a later sweep deletes them.";
                };
              }
              {
                alert = "GarretAuthRefusals";
                expr = "increase(garret_auth_unauthorized_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret refused a valid token from {{ $labels.issuer }} on {{ $labels.instance }}";
                  description = "A token from {{ $labels.issuer }} validated but failed the {{ $labels.claim }} gate on {{ $labels.instance }} in the last hour: a CI ref, repository, or workflow is not in the allow list.";
                };
              }
              {
                alert = "GarretS3Errors";
                expr = "increase(garret_s3_errors_total[15m]) > 5";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret S3 {{ $labels.operation }} errors on {{ $labels.instance }}";
                  description = "{{ $value }} S3 {{ $labels.operation }} requests failed with kind {{ $labels.kind }} on {{ $labels.instance }} in the last 15 minutes.";
                };
              }
              {
                alert = "GarretUploadsShed";
                expr = "increase(garret_uploads_shed_total[1h]) > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret pusher shed uploads on {{ $labels.instance }}";
                  description = "The Pusher on {{ $labels.instance }} answered 429 to uploads in the last hour: raise limits.maxConcurrentUploads or slow the senders.";
                };
              }
              {
                # The gauge holds the weekly fsck's count until the next run.
                alert = "GarretFsckFindings";
                expr = "garret_fsck_findings > 0";
                for = "0m";
                labels.severity = "warning";
                annotations = {
                  summary = "garret fsck found {{ $labels.kind }} rows on {{ $labels.instance }}";
                  description = "The latest garret-admin fsck on {{ $labels.instance }} found {{ $value }} {{ $labels.kind }} rows. See docs/runbooks/garret.md before running fsck --repair.";
                };
              }
              {
                # Fires unconditionally so a dead vmalert, Alertmanager, or
                # webhook shows up in healthchecks.io instead of going quiet.
                alert = "Watchdog";
                expr = "vector(1)";
                for = "0m";
                labels.severity = "none";
                annotations.summary = "Alerting pipeline heartbeat";
              }
            ];
          }
        ];
      };

      prometheus.exporters.blackbox = {
        enable = true;
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
            routes = [
              {
                matchers = [''alertname = "Watchdog"''];
                receiver = "healthchecks";
                group_wait = "0s";
                group_interval = "1m";
                repeat_interval = "5m";
                continue = false;
              }
            ];
          };
          # envsubst-substituted from environmentFile at service start, not
          # Nix interpolation: no `${}` in these URLs.
          receivers = [
            {
              name = "discord-notifications";
              discord_configs = [
                {
                  webhook_url = "$DISCORD_WEBHOOK_URL";
                }
              ];
            }
            {
              name = "healthchecks";
              webhook_configs = [
                {
                  url = "$HEALTHCHECKS_PING_URL";
                  send_resolved = false;
                }
              ];
            }
          ];
        };
      };
    };

    systemd.services = {
      # Without the ordering, journal-upload crash-loops before VictoriaLogs is up and deploy-rs rolls back.
      systemd-journal-upload = {
        after = ["victorialogs.service"];
        wants = ["victorialogs.service"];
      };
      victoriametrics.serviceConfig.MemoryMax = "640M";
      victorialogs.serviceConfig.MemoryMax = "448M";
      victoriatraces.serviceConfig.MemoryMax = "256M";
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
        "alertmanager/healthchecks-ping-url" = {inherit sopsFile;};
      };
      templates = {
        "grafana.env" = {
          owner = "grafana";
          restartUnits = ["grafana.service"];
          content = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder."grafana/oauth-client-secret"}\n";
        };
        "alertmanager.env" = {
          restartUnits = ["alertmanager.service"];
          content = ''
            DISCORD_WEBHOOK_URL=${config.sops.placeholder."alertmanager/discord-webhook"}
            HEALTHCHECKS_PING_URL=${config.sops.placeholder."alertmanager/healthchecks-ping-url"}
          '';
        };
      };
    };
  };
}
