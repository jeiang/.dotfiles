_: let
  mediaDir = "/var/lib/media";
  group = "media";
  # librespeed holds Sonarr's default 8989 on every host (modules/speedtest.nix).
  sonarrPort = 8990;
  seerrPort = 5055;
in {
  flake.lib = {
    mediaGroup = group;
    # One tree for downloads and library: Radarr and Sonarr hardlink imports,
    # and a hardlink cannot cross two impermanence bind mounts.
    mediaDownloadDir = "${mediaDir}/downloads";
    seerrUrl = "http://127.0.0.1:${toString seerrPort}";
  };

  # No port opens in the firewall, so only the trusted NetBird interface
  # reaches these services.
  nixos.modules.artemis = {
    config,
    lib,
    ...
  }: let
    # A static user, not DynamicUser: systemd refuses to hand an existing
    # impermanence bind mount to a dynamic user.
    staticUser = name: {
      users = {
        users.${name} = {
          isSystemUser = true;
          group = name;
        };
        groups.${name} = {};
      };
      systemd.services.${name}.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = name;
        Group = name;
      };
    };
  in
    lib.mkMerge [
      (staticUser "seerr")
      {
        persistence.directories = [
          {
            directory = mediaDir;
            inherit group;
          }
          {
            directory = "/var/lib/radarr";
            user = "radarr";
            inherit group;
          }
          {
            directory = "/var/lib/sonarr";
            user = "sonarr";
            inherit group;
          }
          {
            directory = "/var/lib/seerr";
            user = "seerr";
            group = "seerr";
          }
        ];

        # The operator copies files into the library and tidies it by hand.
        users = {
          groups.${group} = {};
          users.${config.preferences.user.name}.extraGroups = [group];
        };

        services = {
          radarr = {
            enable = true;
            inherit group;
          };
          sonarr = {
            enable = true;
            inherit group;
            settings.server.port = sonarrPort;
          };
          seerr = {
            enable = true;
            port = seerrPort;
            stateRevision = 1;
          };
        };

        # setgid keeps every file in the media group; the tree is world-readable.
        systemd.tmpfiles.settings.media = {
          ${mediaDir}.d = {
            user = "root";
            inherit group;
            mode = "2775";
          };
          "${mediaDir}/movies".d = {
            user = "radarr";
            inherit group;
            mode = "2775";
          };
          "${mediaDir}/tv".d = {
            user = "sonarr";
            inherit group;
            mode = "2775";
          };
        };
      }
    ];
}
