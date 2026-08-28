_: let
  # Peer is the roaming GT-S5360L camera phone: no pinned endpoint, the
  # responder accepts any source address presenting this key.
  phonePublicKey = "E0SeA+k/Wf6Wz0nn+2q/PIlI4Nrb0wVX8UTVV9DCrhg=";
in {
  flake.nixosModules.camera-ingest = {
    config,
    pkgs,
    ...
  }: {
    sops = {
      secrets = {
        "wireguard/camera-node1-private-key".sopsFile = ./secrets.yaml;
        "pixeldrain/api-key".sopsFile = ./secrets.yaml;
      };
      templates."camera-relay.env" = {
        restartUnits = ["camera-relay.service"];
        content = ''
          RCLONE_CONFIG_PIXELDRAIN_TYPE=pixeldrain
          RCLONE_CONFIG_PIXELDRAIN_API_KEY=${config.sops.placeholder."pixeldrain/api-key"}
        '';
      };
    };

    networking = {
      wireguard.interfaces.wg-camera = {
        ips = ["10.100.1.1/30"];
        listenPort = 51822;
        privateKeyFile = config.sops.secrets."wireguard/camera-node1-private-key".path;
        peers = [
          {
            publicKey = phonePublicKey;
            allowedIPs = ["10.100.1.2/32"];
          }
        ];
      };
      firewall.interfaces.wg-camera.allowedTCPPorts = [8090];
    };

    # Upload receiver: the phone PUTs date-pathed JPEGs via nginx DAV; a 2xx
    # is the phone's cue to delete its SD copy, so the spool is the durable hop.
    services.nginx = {
      enable = true;
      virtualHosts.camera-ingest = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 8090;
          }
        ];
        root = "/var/spool/camera-ingest";
        extraConfig = ''
          dav_methods PUT;
          create_full_put_path on;
          client_max_body_size 16m;
        '';
      };
    };

    systemd = {
      services = {
        nginx.serviceConfig = {
          MemoryMax = "128M";
          # nginx runs ProtectSystem=strict; without this every PUT dies with
          # EROFS (surfaced as a 500).
          ReadWritePaths = ["/var/spool/camera-ingest"];
        };
        # Moves the spool onward to Pixeldrain, deleting local copies only
        # after Pixeldrain confirms.
        camera-relay = {
          serviceConfig = {
            Type = "oneshot";
            User = "nginx";
            Group = "nginx";
            EnvironmentFile = config.sops.templates."camera-relay.env".path;
            ExecStart = "${pkgs.rclone}/bin/rclone --config /dev/null move /var/spool/camera-ingest pixeldrain:camera --delete-empty-src-dirs";
            MemoryMax = "128M";
          };
        };
      };
      timers.camera-relay = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "1m";
        };
      };
      tmpfiles.rules = ["d /var/spool/camera-ingest 0750 nginx nginx -"];
    };
  };
}
