_: let
  mediaDir = "/var/lib/media";
  group = "media";
  # One darkhttpd per library root, so the URL path is the library path.
  libraryServers = {
    movies = 8084;
    tv = 8085;
  };
in {
  flake.lib = {
    inherit mediaDir;
    mediaMoviesPort = libraryServers.movies;
    mediaTvPort = libraryServers.tv;
    mediaGroup = group;
    mediaDownloadDir = "${mediaDir}/downloads";
  };

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: {
    persistence.directories = [
      {
        directory = mediaDir;
        inherit group;
      }
      # Retired media-organizer's state, kept until its rules are imported into atrium:
      # dropping this bind mount cannot switch live, so it goes in a later --boot deploy.
      {
        directory = "/var/lib/media-organizer";
        user = "media-organizer";
        inherit group;
        mode = "0700";
      }
    ];

    # The operator copies files into the library and tidies it by hand.
    users = {
      groups.${group} = {};
      users.${config.preferences.user.name}.extraGroups = [group];
      users.media-organizer = {
        isSystemUser = true;
        inherit group;
      };
    };

    # setgid keeps every file in the media group; the tree is world-readable.
    systemd.tmpfiles.settings.media = lib.genAttrs (map (d: "${mediaDir}${d}") ["" "/import" "/movies" "/tv"]) (_: {
      d = {
        user = "root";
        inherit group;
        mode = "2775";
      };
    });

    # Read-only direct links over the mesh, listening on every interface but in
    # no allowedTCPPorts: only the trusted NetBird interface reaches them. The
    # nixpkgs darkhttpd module runs a single instance, hence plain units.
    # `--ipv6` with `::` also takes IPv4 (see modules/qbittorrent).
    systemd.services = lib.mapAttrs' (library: port:
      lib.nameValuePair "darkhttpd-${library}" {
        description = "Dark HTTPd for the ${library} library";
        wants = ["network.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.darkhttpd)
            "${mediaDir}/${library}"
            "--port"
            (toString port)
            "--addr"
            "::"
            "--ipv6"
            "--no-server-id"
          ];
          DynamicUser = true;
          Restart = "on-failure";
          RestartSec = "2s";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          ReadOnlyPaths = ["${mediaDir}/${library}"];
        };
      })
    libraryServers;
  };
}
