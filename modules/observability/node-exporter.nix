{
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
