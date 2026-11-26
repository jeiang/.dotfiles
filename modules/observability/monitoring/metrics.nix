{
  self,
  config,
  lib,
  ...
}: let
  inherit (config.monitoring) scrape;
  smartctlPort = self.nixosConfigurations.artemis.config.services.prometheus.exporters.smartctl.port;
in {
  nixos.modules.artemis.services.prometheus.exporters.smartctl = {
    enable = true;
    extraFlags = ["--log.level=warn"];
  };

  netbird.meshFlows.smartctl = [{port = smartctlPort;}];

  monitoring.scrape.smartctl = {
    type = "node";
    targets = ["${self.lib.netbirdPeers.artemis}:${toString smartctlPort}"];
  };

  nixos.modules.monitoring = {
    services.victoriametrics = {
      enable = true;
      listenAddress = ":8428";
      # "1" = one month; unsuffixed retentionPeriod values count months.
      retentionPeriod = "1";
      prometheusConfig.scrape_configs = lib.mapAttrsToList (job_name: job:
        {
          inherit job_name;
          static_configs = [
            {
              inherit (job) targets;
              labels.type = job.type;
            }
          ];
        }
        // job.settings)
      scrape;
    };

    systemd.services.victoriametrics.serviceConfig.MemoryMax = "640M";
  };
}
