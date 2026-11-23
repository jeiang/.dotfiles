{
  self,
  config,
  ...
}: let
  port = config.legion.services.monitoring.ports.victoria-traces;
in {
  flake.lib = {
    # OTLP/HTTP base URL; an OTel SDK appends /v1/traces.
    otlpTracesEndpoint = fromNode: "http://${self.lib.serviceAddress fromNode "monitoring"}:${toString port}/insert/opentelemetry";

    # Environment for an OTel SDK that exports traces from fromNode.
    otlpTracesEnv = fromNode: serviceName: {
      OTEL_SERVICE_NAME = serviceName;
      OTEL_TRACES_EXPORTER = "otlp";
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "${self.lib.otlpTracesEndpoint fromNode}/v1/traces";
    };
  };

  monitoring.scrape.victoriatraces = {
    type = "monitoring";
    targets = ["127.0.0.1:${toString port}"];
  };

  nixos.modules.monitoring = {config, ...}: {
    # OTLP over HTTP at /insert/opentelemetry/v1/traces.
    services.victoriatraces = {
      enable = true;
      listenAddress = ":${toString port}";
      inherit (config.services.victoriametrics) retentionPeriod;
      # A chatty sender must not fill the root disk the metrics and logs share.
      extraOptions = ["-retention.maxDiskSpaceUsageBytes=5GiB"];
    };

    systemd.services.victoriatraces.serviceConfig.MemoryMax = "256M";
  };
}
