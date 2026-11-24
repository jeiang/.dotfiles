{
  self,
  config,
  ...
}: let
  hostname = "grafana.jeiang.dev";
  port = config.legion.services.monitoring.ports.grafana;
in {
  flake.lib = {
    # Mesh address, not the public hostname: probing the edge gets the client banned by CrowdSec.
    grafanaMeshUrl = "http://${self.lib.serviceMeshAddress "monitoring"}:${toString port}";
    grafanaMetricsDatasourceUid = "victoriametrics";
    grafanaPublicUrl = "https://${hostname}";
  };

  gatus.endpoints.Grafana = {
    group = "Services";
    url = "https://${hostname}/api/health";
  };

  # Ungated: its clients are machines, for which a proof-of-work interstitial is an outage.
  nixos.modules.edge = {config, ...}: {
    edge.sites.${hostname}.config = "reverse_proxy ${self.lib.serviceAddress config.networking.hostName "monitoring"}:${toString port}";
  };

  nixos.modules.monitoring = {
    config,
    pkgs,
    ...
  }: let
    sopsFile = ./secrets.yaml;
  in {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          domain = hostname;
          root_url = "https://${hostname}";
          http_addr = "0.0.0.0";
          http_port = port;
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
            uid = self.lib.grafanaMetricsDatasourceUid;
            url = "http://127.0.0.1${config.services.victoriametrics.listenAddress}";
            isDefault = true;
          }
          {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            uid = "victorialogs";
            url = "http://127.0.0.1${config.services.victorialogs.listenAddress}";
          }
          {
            name = "VictoriaTraces";
            type = "jaeger";
            uid = "victoriatraces";
            url = "http://127.0.0.1${config.services.victoriatraces.listenAddress}/select/jaeger";
          }
        ];
        dashboards.settings.providers = [
          {
            name = "default";
            options.path = ./dashboards;
          }
          {
            name = "atrium";
            options.path = pkgs.runCommand "atrium-dashboards" {} ''
              mkdir -p $out
              cp ${config.services.atrium.monitoring.dashboardFile} $out/atrium.json
            '';
          }
          {
            name = "mail-organizer";
            options.path = pkgs.runCommand "mail-organizer-dashboards" {} ''
              mkdir -p $out
              cp ${config.services.mail-organizer.monitoring.dashboardFile} $out/mail-organizer.json
            '';
          }
        ];
      };
      declarativePlugins = with pkgs.grafanaPlugins; [prometheus victoriametrics-logs-datasource jaeger];
    };

    systemd.services.grafana = {
      # services.grafana has no environmentFile option, so this is wired
      # directly onto the systemd unit.
      serviceConfig = {
        MemoryMax = "320M";
        EnvironmentFile = config.sops.templates."grafana.env".path;
      };
    };

    sops = {
      secrets = {
        "grafana/oauth-client-secret" = {inherit sopsFile;};
        "grafana/secret-key" = {
          inherit sopsFile;
          owner = "grafana";
          restartUnits = ["grafana.service"];
        };
      };
      templates."grafana.env" = {
        owner = "grafana";
        restartUnits = ["grafana.service"];
        content = "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder."grafana/oauth-client-secret"}\n";
      };
    };
  };
}
