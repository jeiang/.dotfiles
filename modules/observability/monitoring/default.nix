{
  self,
  config,
  lib,
  ...
}: let
  legionServices = config.legion.services;
  monitoringNode = legionServices.monitoring.node;
  inherit (legionServices.monitoring) ports;
in {
  options.monitoring = {
    scrape = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.str;
            description = "The `type` label on every target.";
          };
          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
          settings = lib.mkOption {
            type = lib.types.attrsOf lib.types.raw;
            default = {};
            description = "Scrape config attributes set over the generated job, such as `scheme` or `static_configs`.";
          };
        };
      });
      default = {};
      description = "VictoriaMetrics scrape jobs, keyed by job name; each feature adds its own.";
    };

    probes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          module = lib.mkOption {type = lib.types.enum ["http_2xx" "tcp_connect" "dns"];};
          tier = lib.mkOption {type = lib.types.enum ["critical" "warning"];};
          targets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "`host:port` targets, with a path for http_2xx.";
          };
        };
      });
      default = {};
      description = "Blackbox exporter probes of private backend addresses; each feature adds its own.";
    };
  };

  config = {
    # Where the monitoring node reaches a service port; empty while that node is mesh-only without a peer entry.
    flake.lib.monitoringTargets = service: key: path: let
      address = self.lib.serviceAddress monitoringNode service;
    in
      lib.optional (address != null) "${address}:${toString legionServices.${service}.ports.${key}}${path}";

    legion.services.monitoring = {
      node = "zantark";
      module = "monitoring";
      units = ["grafana" "victoriametrics" "victorialogs" "victoriatraces" "vmalert-default" "alertmanager" "prometheus-blackbox-exporter"];
      ports = {
        grafana = 3000;
        victoria-logs = 9428;
        victoria-traces = 10428;
      };
    };

    netbird.meshFlows.monitoring = map (port: {inherit port;}) (builtins.attrValues ports);
  };
}
