{
  flake.nixosModules.monitoring = {config, ...}: let
    port = 2342;
    addr = "0.0.0.0";
  in {
    services = {
      grafana = {
        enable = true;
        settings = {
          server = {
            http_port = port;
            http_addr = addr;
            # enforce_domain = true;
            root_url = "https://grafana.jeiang.dev";
            domain = "grafana.jeiang.dev";
          };
          security.secret_key = "$__file{${config.sops.secrets."grafana/secret-key".path}}";
          analytics.reporting_enabled = false;
          "auth.generic_oauth" = {
            enabled = "true";
            name = "Authelia";
            icon = "signin";
            client_id = "grafana";
            client_secret = "$__file{${config.sops.secrets."authelia/oidc/clients/grafana-raw".path}}";
            scopes = "openid profile email groups offline_access";
            empty_scopes = "false";
            auth_url = "https://auth.jeiang.dev/api/oidc/authorization";
            token_url = "https://auth.jeiang.dev/api/oidc/token";
            api_url = "https://auth.jeiang.dev/api/oidc/userinfo";
            login_attribute_path = "preferred_username";
            groups_attribute_path = "groups";
            name_attribute_path = "name";
            use_pkce = "true";
            role_attribute_path = "contains(groups[*], 'grafana-admin') && 'Admin' || contains(groups[*], 'grafana-editor') && 'Editor' || 'Viewer'";
            auth_style = "InHeader";
            auto_login = true;
          };
          "auth.basic" = {
            enabled = false;
          };
        };
      };
      prometheus = {
        enable = true;
        port = 9001;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = ["systemd"];
            port = 9002;
          };
        };
        scrapeConfigs = [
          {
            job_name = config.networking.hostName;
            static_configs = [
              {
                targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
              }
            ];
          }
        ];
      };
      authelia.instances.main = {
        settings.identity_providers.oidc = {
          claims_policies.grafana.id_token = [
            "email"
            "name"
            "preferred_username"
            "groups"
          ];
          clients = [
            {
              client_id = "grafana";
              claims_policy = "grafana";
              audience = "grafana";
              client_name = "Grafana";
              client_secret = ''{{ secret "${config.sops.secrets."authelia/oidc/clients/grafana".path}" }}'';
              public = false;
              authorization_policy = "two_factor";
              require_pkce = true;
              pkce_challenge_method = "S256";
              redirect_uris = [
                "https://grafana.jeiang.dev/login/generic_oauth"
              ];
              scopes = [
                "openid"
                "email"
                "profile"
                "offline_access"
                "groups"
              ];
              response_types = [
                "code"
              ];
              grant_types = [
                "authorization_code"
              ];
              userinfo_signed_response_alg = "none";
              access_token_signed_response_alg = "none";
              token_endpoint_auth_method = "client_secret_basic";
            }
          ];
        };
      };
      caddy.virtualHosts.grafana = rec {
        hostName = "grafana.jeiang.dev";
        logFormat = null;
        extraConfig = ''
          import logging ${hostName}
          import compression
          import security_headers

          reverse_proxy ${addr}:${toString port}
        '';
      };
      loki = {
        enable = true;
        configuration = {
          auth_enabled = false;
          server = {
            http_listen_port = 3100;
          };
          common = {
            instance_addr = "127.0.0.1";
            path_prefix = "/var/lib/loki";
            replication_factor = 1;
            ring = {
              kvstore = {
                store = "inmemory";
              };
            };
          };
          schema_config = {
            configs = [
              {
                from = "2024-04-01";
                store = "tsdb";
                object_store = "filesystem";
                schema = "v13";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];
          };
          storage_config = {
            filesystem = {
              directory = "/var/lib/loki/chunks";
            };
          };
          query_range = {
            results_cache = {
              cache = {
                embedded_cache = {
                  enabled = true;
                  max_size_mb = 100;
                };
              };
            };
          };
          limits_config = {
            allow_structured_metadata = true;
            volume_enabled = true;
          };
          compactor = {
            working_directory = "/var/lib/loki/compactor";
            retention_enabled = true;
            delete_request_store = "filesystem";
          };
          ruler = {
            storage = {
              type = "local";
              local = {
                directory = "/var/lib/loki/rules";
              };
            };
            rule_path = "/var/lib/loki/rules-temp";
          };
        };
      };
      alloy.enable = true;
    };
    environment.etc."alloy/10-main.alloy".text = ''
      loki.write "local" {
        endpoint {
          url = "http://localhost:3100/loki/api/v1/push"
        }
      }

      discovery.relabel "journal" {
        targets = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "systemd" {
        max_age       = "24h"
        relabel_rules = discovery.relabel.journal.rules

        labels = {
          job = "systemd-journal",
        }

        forward_to = [loki.write.local.receiver]
      }
    '';
    sops.secrets = {
      "authelia/oidc/clients/grafana".owner = "authelia-main";
      "authelia/oidc/clients/grafana-raw".owner = "grafana";
      "grafana/secret-key".owner = "grafana";
    };
  };
}
