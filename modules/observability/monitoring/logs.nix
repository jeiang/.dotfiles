{config, ...}: let
  port = config.legion.services.monitoring.ports.victoria-logs;
in {
  nixos.modules.monitoring = {config, ...}: {
    services.victorialogs = {
      enable = true;
      listenAddress = ":${toString port}";
      extraOptions = ["-retentionPeriod=${config.services.victoriametrics.retentionPeriod}" "-retention.maxDiskSpaceUsageBytes=10GiB"];
    };

    systemd.services = {
      # Without the ordering, journal-upload crash-loops before VictoriaLogs is up and deploy-rs rolls back.
      systemd-journal-upload = {
        after = ["victorialogs.service"];
        wants = ["victorialogs.service"];
      };
      victorialogs.serviceConfig.MemoryMax = "448M";
    };
  };
}
