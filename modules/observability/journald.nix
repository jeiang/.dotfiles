{
  self,
  config,
  ...
}: let
  victoriaLogsPort = config.legion.services.monitoring.ports.victoria-logs;
in {
  nixos.modules = {
    base = {config, ...}: {
      services.journald = {
        settings.Journal.SystemMaxUse = "1G";
        # systemd-journal-upload appends `/upload` itself and VictoriaLogs' route is /insert/journald/upload, so this URL must end at /insert/journald.
        upload = {
          enable = true;
          settings.Upload.URL = "http://${self.lib.serviceAddress config.networking.hostName "monitoring"}:${toString victoriaLogsPort}/insert/journald";
        };
      };
      monitoredUnits = ["systemd-journal-upload.service"];

      # determinate-nixd 3.24 cannot parse one kind of Nix result message and logs a warning with a two-line span for each, mostly binary cache 404s.
      systemd.services.nix-daemon.serviceConfig.LogFilterPatterns = [
        "~Unparsed.Nix.daemon.log.line"
        "~at.src/api/logger[.]rs"
        "~in.determinate_nixd::api::logger::handle_connection"
        "~reaped.child.process.*succeeded"
      ];

      # systemd refuses a /var/lib/private that is not 0700, so the whole directory is the entry; it holds the upload cursor.
      persistence.directories = [
        {
          directory = "/var/lib/private";
          mode = "0700";
        }
      ];
    };

    artemis = {
      # logind rejects the version string NixOS writes into every systemd-boot entry, once per entry each time it lists them.
      systemd.services.systemd-logind.serviceConfig.LogFilterPatterns = "~is.not.a.valid.version";
    };
  };
}
