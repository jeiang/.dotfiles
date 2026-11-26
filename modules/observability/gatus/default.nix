{
  self,
  config,
  lib,
  ...
}: let
  port = 8086;
  statusHostname = "status.jeiang.dev";

  base = {
    web.port = port;

    # In-memory deliberately: keeps this service stateless and off the
    # backup path.
    storage.type = "memory";

    ui = {
      title = "Status | jeiang.dev";
      header = "jeiang.dev";
      link = "https://jeiang.dev";
      dashboard-heading = "Service Status";
      dashboard-subheading = "Live checks against the fleet's public endpoints";
    };

    endpoints =
      lib.mapAttrsToList (name: endpoint: {inherit name;} // endpoint) config.gatus.endpoints;
  };

  # The Anubis-protected sites resolve to the edge's private or mesh
  # address, which the edge serves without a challenge.
  contentSiteHosts = hostName: {
    ${self.lib.legionAddress hostName config.legion.services.caddy.node} = self.lib.websiteHostnames ++ self.lib.portfolioHostnames;
  };

  instance = {
    settings,
    alerts ? [],
  }: {config, ...}: {
    networking.hosts = contentSiteHosts config.networking.hostName;

    services.gatus = {
      enable = true;
      settings =
        base
        // settings
        // lib.optionalAttrs (alerts != []) {
          endpoints = map (endpoint: endpoint // {inherit alerts;}) base.endpoints;
        };
    };

    systemd.services.gatus = {
      serviceConfig.MemoryMax = "64M";
      # A running Gatus keeps resolving through the hosts table it started with.
      restartTriggers = [(builtins.toJSON config.networking.hosts)];
    };
  };

  placement = {
    gatus = "zantark";
    gatus-atl = "ricklent";
  };
in {
  options.gatus.endpoints = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        group = lib.mkOption {type = lib.types.str;};
        url = lib.mkOption {type = lib.types.str;};
        conditions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["[STATUS] == 200"];
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "2m";
        };
      };
    });
    default = {};
    description = "Status page checks, keyed by the name Gatus shows; each feature adds its own.";
  };

  config = {
    flake.lib.gatusServices = builtins.attrNames placement;

    monitoring.scrape.gatus = {
      type = "probe";
      targets = self.lib.monitoringTargets "gatus" "app" "";
    };

    legion.services =
      lib.mapAttrs (module: node: {
        inherit node module;
        units = ["gatus"];
        ports.app = port;
      })
      placement;

    nixos.modules = {
      # Ungated deliberately: it reports on Pocket ID, so SSO (or
      # netbird-proxy, which authenticates against it) would take the
      # outage report down with the outage. appsec skipped, fail-open.
      edge = {config, ...}: {
        edge.sites.${statusHostname} = {
          appsec = false;
          config = "reverse_proxy ${self.lib.serviceAddress config.networking.hostName "gatus"}:${toString port}";
        };
      };

      gatus = instance {
        # Scraped by VictoriaMetrics so a failed check reaches Alertmanager;
        # the dashboard alone never notifies anyone.
        settings.metrics = true;
      };

      # Alerts straight to Discord so the watchdog does not depend on zantark.
      gatus-atl = {config, ...}: {
        imports = [
          (instance {
            settings.alerting.discord = {
              webhook-url = "\${DISCORD_WEBHOOK_URL}";
              default-alert = {
                failure-threshold = 5;
                success-threshold = 2;
                send-on-resolved = true;
              };
            };
            alerts = [{type = "discord";}];
          })
        ];

        services.gatus.environmentFile = config.sops.templates."gatus.env".path;

        sops = {
          secrets."discord-webhook".sopsFile = ./secrets.yaml;
          templates."gatus.env" = {
            restartUnits = ["gatus.service"];
            content = "DISCORD_WEBHOOK_URL=${config.sops.placeholder."discord-webhook"}\n";
          };
        };
      };
    };
  };
}
