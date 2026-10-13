{self, ...}: let
  port = 8083;
  user = "media-organizer";
  stateDir = "/var/lib/${user}";
  tokenSecret = "media-organizer/ntfy-token";
in {
  flake.lib.mediaOrganizerPort = port;

  perSystem = {pkgs, ...}: {
    packages.media-organizer = pkgs.buildGoModule {
      pname = "media-organizer";
      version = "0.1.0";
      src = ./app;
      vendorHash = null;
      meta.mainProgram = "media-organizer";
    };
  };

  # Files finished torrents (hardlinks, so they keep seeding) and import/
  # entries (moves) into the library after the operator confirms each name,
  # and watches EZTV for the operator's release rules.
  # Mesh-only like atrium: the port is in no allowedTCPPorts.
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: {
    users = {
      users.${user} = {
        isSystemUser = true;
        group = self.lib.mediaGroup;
      };
    };

    persistence.directories = [
      {
        directory = stateDir;
        inherit user;
        group = self.lib.mediaGroup;
        mode = "0700";
      }
    ];

    sops.secrets.${tokenSecret} = {
      sopsFile = ./secrets.yaml;
      owner = user;
      restartUnits = ["${user}.service"];
    };

    systemd.services.${user} = {
      description = "Media organizer";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.media-organizer)
          "-listen"
          "0.0.0.0:${toString port}"
          "-qbittorrent"
          "http://127.0.0.1:${toString self.lib.qbittorrentWebuiPort}"
          "-media"
          self.lib.mediaDir
          "-state"
          "${stateDir}/state.json"
          "-ntfy-url"
          self.lib.ntfyBaseUrl
          "-ntfy-topic"
          self.lib.ntfyMediaTopic
          "-ntfy-token-file"
          config.sops.secrets.${tokenSecret}.path
          "-public-url"
          "http://${self.deploy.nodes.artemis.hostname}:${toString port}"
        ];
        User = user;
        Group = self.lib.mediaGroup;
        UMask = "0002";
        StateDirectory = user;
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 5;
        ProtectSystem = "strict";
        ReadWritePaths = [self.lib.mediaDir];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
