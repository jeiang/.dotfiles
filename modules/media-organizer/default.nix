{self, ...}: let
  port = 8083;
  user = "media-organizer";
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
  # entries (moves) into the library after the operator confirms each name.
  # Mesh-only like atrium: the port is in no allowedTCPPorts.
  nixos.modules.artemis = {
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
        ];
        User = user;
        Group = self.lib.mediaGroup;
        UMask = "0002";
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
