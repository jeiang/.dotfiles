{
  self,
  inputs,
  ...
}: let
  stateDir = "/var/lib/mail-organizer";
  metricsPort = 9490;
  # Grafana Explore on a Jaeger trace id; `{trace_id}` is filled in by mail-organizer.
  traceUrl = "${self.lib.grafanaPublicUrl}/explore?schemaVersion=1&panes=%7B%22t%22:%7B%22datasource%22:%22victoriatraces%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22datasource%22:%7B%22type%22:%22jaeger%22,%22uid%22:%22victoriatraces%22%7D,%22query%22:%22{trace_id}%22%7D%5D,%22range%22:%7B%22from%22:%22now-30d%22,%22to%22:%22now%22%7D%7D%7D";
in {
  netbird.meshFlows.mail-organizer = [{port = metricsPort;}];

  monitoring.scrape.mail-organizer = {
    type = "app";
    targets = ["${self.lib.netbirdPeers.artemis}:${toString metricsPort}"];
  };

  # The dashboard and alert rules ship with the module.
  nixos.modules.monitoring.imports = [inputs.mail-organizer.nixosModules.default];

  nixos.modules.media = {
    config,
    lib,
    ...
  }: let
    secret = name: config.sops.secrets."mail-organizer/${name}".path;
  in {
    imports = [inputs.mail-organizer.nixosModules.default];

    services.mail-organizer = {
      enable = true;
      metricsListen = "${self.lib.netbirdPeers.artemis}:${toString metricsPort}";
      traceUrlTemplate = traceUrl;
      accounts = {
        icloud = {
          preset = "icloud";
          login = "aidan@aidanpinard.co";
          passwordFile = secret "icloud";
        };
        gmail = {
          preset = "gmail";
          login = "otakuman86@gmail.com";
          passwordFile = secret "gmail";
        };
      };
      telemetry = {
        enable = true;
        endpoint = self.lib.otlpTracesEndpoint config.networking.hostName;
        sampleRatio = 1.0;
      };
    };

    # Not started until atrium's history is imported into an empty database.
    systemd.services.mail-organizer.wantedBy = lib.mkForce [];

    monitoredUnits = ["mail-organizer.service"];

    persistence.directories = [
      {
        directory = stateDir;
        user = "mail-organizer";
        group = "mail-organizer";
        mode = "0700";
      }
    ];
    backups.persist.paths = [stateDir];

    sops.secrets = lib.genAttrs ["mail-organizer/icloud" "mail-organizer/gmail"] (_: {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["mail-organizer.service"];
    });
  };
}
