{
  nixos.modules.artemis = {
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
        matches any run of characters.
      '';
    };

    config.services.prometheus.exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        extraFlags = ["--collector.systemd.unit-include=${lib.concatMapStringsSep "|" unitRegex config.monitoredUnits}"];
      };
      # Scraped from zantark over the mesh: the btrfs pool is RAID0, so one failing drive loses it.
      smartctl.enable = true;
    };
  };
}
