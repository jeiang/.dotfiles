_: let
  mediaDir = "/var/lib/media";
  # icloud-import stages files in incoming (rsync creates it) and moves each
  # finished item into import.
  importDir = "${mediaDir}/import";
  incomingDir = "${mediaDir}/.incoming";
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
    mediaImportDir = importDir;
    mediaIncomingDir = incomingDir;
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
    ];
    monitoredUnits = map (library: "darkhttpd-${library}.service") (lib.attrNames libraryServers);

    # The operator copies files into the library and tidies it by hand.
    users = {
      groups.${group} = {};
      users.${config.preferences.user.name}.extraGroups = [group];
    };

    # setgid keeps every file in the media group; the tree is world-readable.
    systemd.tmpfiles.settings.media = lib.genAttrs ([mediaDir importDir] ++ map (library: "${mediaDir}/${library}") (lib.attrNames libraryServers)) (_: {
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
