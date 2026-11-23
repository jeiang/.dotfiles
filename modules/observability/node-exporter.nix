{
  self,
  config,
  lib,
  ...
}: let
  monitoringNode = config.legion.services.monitoring.node;
  exporterPort = host: self.nixosConfigurations.${host}.config.services.prometheus.exporters.node.port;
  # A node outside the private network is scraped over the mesh and drops out until it has a peer entry.
  addresses = builtins.filter (a: a != null) (map (self.lib.legionAddress monitoringNode) (builtins.attrNames self.lib.legionNodes));
  meshOnlyNodes = builtins.attrNames (lib.filterAttrs (_: n: n.privateIPv4 == null) self.lib.legionNodes);
in {
  flake.lib = {
    nodeExporterHosts = addresses ++ [self.lib.netbirdPeers.artemis];
    nodeExporterTargets =
      map (ip: "${ip}:${toString (exporterPort monitoringNode)}") addresses
      ++ ["${self.lib.netbirdPeers.artemis}:${toString (exporterPort "artemis")}"];
  };

  netbird.meshFlows.node-exporter = map (host: {port = exporterPort host;}) (meshOnlyNodes ++ ["artemis"]);

  monitoring.scrape.node = {
    type = "node";
    targets = self.lib.nodeExporterTargets;
  };

  nixos.modules.base = {
    config,
    lib,
    ...
  }: let
    unitRegex = unit: builtins.replaceStrings ["\\*"] [".*"] (lib.escapeRegex unit);
  in {
    options.monitoredUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        systemd units the node exporter reports, as unit names in which `*`
        matches any run of characters. Each module adds the units it owns.
      '';
    };

    config.services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = ["systemd"];
      # An explicit list keeps node_systemd_unit_state cardinality bounded for the memory-constrained VictoriaMetrics; the default `.+` would emit hundreds of series.
      extraFlags = ["--collector.systemd.unit-include=${lib.concatMapStringsSep "|" unitRegex (lib.unique config.monitoredUnits)}"];
    };
  };
}
