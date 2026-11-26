{self, ...}: {
  nixos.modules.monitoring = {config, ...}: let
    sopsFile = ./secrets.yaml;
  in {
    services.vmalert.instances.default = {
      enable = true;
      settings = {
        "datasource.url" = "http://127.0.0.1${config.services.victoriametrics.listenAddress}";
        "notifier.url" = ["http://127.0.0.1:${toString config.services.prometheus.alertmanager.port}"];
        rule = [config.services.mail-organizer.monitoring.ruleFile];
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
              alert = "VictoriaTracesDiskFilling";
              expr = "sum by (job, instance) (vt_data_size_bytes) / (sum by (job, instance) (vt_free_disk_space_bytes) + sum by (job, instance) (vt_data_size_bytes)) > 0.8";
              for = "30m";
              labels.severity = "critical";
              annotations = {
                summary = "VictoriaTraces data fills its disk on {{ $labels.instance }}";
                description = "Trace data on {{ $labels.instance }} takes over 80% of the disk it shares with the free space. Lower -retention.maxDiskSpaceUsageBytes or the ingestion rate.";
              };
            }
            {
              alert = "VictoriaTracesQueryLimit";
              expr = "avg_over_time(vt_concurrent_select_current[1m]) >= vt_concurrent_select_capacity";
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "VictoriaTraces on {{ $labels.instance }} keeps hitting its concurrent query limit";
                description = "Queries on {{ $labels.instance }} have been at -search.maxConcurrentRequests for 15 minutes.";
              };
            }
            {
              alert = "VictoriaTracesQueryTimeouts";
              expr = "increase(vt_concurrent_select_limit_timeout_total[5m]) > 0";
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "VictoriaTraces queries time out on {{ $labels.instance }}";
                description = "Queries on {{ $labels.instance }} waited past -search.maxQueueDuration and failed in the last 15 minutes.";
              };
            }
            {
              alert = "VictoriaTracesSpansDropped";
              expr = "rate(vt_rows_dropped_total[5m]) > 0";
              for = "0m";
              labels.severity = "warning";
              annotations = {
                summary = "VictoriaTraces drops spans on {{ $labels.instance }}";
                description = "{{ $labels.instance }} rejected spans with timestamps outside the retention window; the sender's clock or batching is wrong.";
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

    services.prometheus.alertmanager = {
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

    systemd.services = {
      "vmalert-default".serviceConfig.MemoryMax = "128M";
      alertmanager.serviceConfig.MemoryMax = "96M";
    };

    sops = {
      secrets = {
        "alertmanager/discord-webhook" = {inherit sopsFile;};
        "alertmanager/healthchecks-ping-url" = {inherit sopsFile;};
      };
      templates."alertmanager.env" = {
        restartUnits = ["alertmanager.service"];
        content = ''
          DISCORD_WEBHOOK_URL=${config.sops.placeholder."alertmanager/discord-webhook"}
          HEALTHCHECKS_PING_URL=${config.sops.placeholder."alertmanager/healthchecks-ping-url"}
        '';
      };
    };
  };
}
