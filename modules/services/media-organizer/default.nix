{
  self,
  inputs,
  ...
}: let
  stateDir = "/var/lib/media-organizer";
  cacheDir = "/var/cache/media-organizer";
  port = 8090;
in {
  flake.lib.mediaOrganizerPort = port;

  nixos.modules.media = {config, ...}: let
    cfg = config.services.media-organizer;
  in {
    imports = [inputs.media-organizer.nixosModules.default];

    # Every interface but in no allowedTCPPorts, like the darkhttpd libraries: only the
    # trusted NetBird interface reaches it, and the app has no login.
    services.media-organizer = {
      enable = true;
      listen = "[::]:${toString port}";
      inherit (self.lib) mediaDir;
      group = self.lib.mediaGroup;
      downloadsDir = self.lib.mediaDownloadDir;
      importDir = self.lib.mediaImportDir;
      qbittorrent = {
        url = "http://127.0.0.1:${toString self.lib.qbittorrentWebuiPort}";
        apiKeyFile = self.lib.qbittorrentApiKeyFile;
      };
      tmdbTokenFile = config.sops.secrets."media-organizer/tmdb-token".path;
    };

    # Root-owned; the unit reads it as a systemd credential.
    sops.secrets."media-organizer/tmdb-token" = {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["media-organizer.service"];
    };

    systemd.services.media-organizer = {
      wants = [self.lib.qbittorrentApiKeyUnit];
      after = [self.lib.qbittorrentApiKeyUnit];
    };

    monitoredUnits = ["media-organizer.service"];

    persistence.directories = [
      {
        directory = stateDir;
        inherit (cfg) user group;
        mode = "0700";
      }
      {
        directory = cacheDir;
        inherit (cfg) user group;
        mode = "0700";
      }
    ];
    backups.persist.paths = [stateDir];
  };
}
