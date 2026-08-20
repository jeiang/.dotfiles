_: let
  # Static keypair per endpoint, private halves in ./secrets.yaml (same
  # shape as modules/nixos/backup-tunnel). The peer is the GT-S5360L
  # camera phone (phone-root-test repo), which runs its own in-app
  # WireGuard implementation and roams across Wi-Fi networks -- no
  # endpoint is pinned here; the responder accepts any source address
  # presenting the phone's key.
  phonePublicKey = "E0SeA+k/Wf6Wz0nn+2q/PIlI4Nrb0wVX8UTVV9DCrhg=";
in {
  # legion-node1: responder + upload receiver. Placed via the service
  # inventory (modules/hosts/legion/_service-inventory.nix
  # "camera-ingest"), which opens UDP 51822 on the host firewall. The
  # Hetzner Cloud Firewall is a manual per-port gate -- 51822/udp must be
  # opened there too, same as backup-tunnel's 51821.
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
      # Env-var-defined rclone remote: no config file to manage, and the
      # EnvironmentFile is read by systemd as root before privileges drop,
      # so the template needs no owner (garret-s3.env precedent).
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
      # The receiver port is reachable only over the tunnel: 0.0.0.0 bind
      # plus an interface-scoped opening (the crowdsec/blocky
      # "0.0.0.0-plus-firewall" pattern), which also avoids ordering nginx
      # after the wg-camera address exists.
      firewall.interfaces.wg-camera.allowedTCPPorts = [8090];
    };

    # The "ingest application" is nginx's in-tree DAV module: the phone
    # PUTs /YYYY/MM/DD/<name>.jpg, create_full_put_path makes the date
    # directories, and the body is written to a temp file then renamed
    # into place -- a watcher on the spool can never observe a
    # half-written upload. 2xx here is the phone's cue to delete its SD
    # copy, so the spool is the durable hop until the Pixeldrain relay
    # (separate increment) moves files onward.
    services.nginx = {
      enable = true;
      virtualHosts.camera-ingest = {
        # Port 8090: node1's crowdsec LAPI already binds 0.0.0.0:8080.
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
          # The nginx unit runs ProtectSystem=strict and only whitelists
          # its own log/cache dirs; without this every PUT dies with EROFS
          # (surfaced as a 500).
          ReadWritePaths = ["/var/spool/camera-ingest"];
        };
        # Relay: everything in the spool moves onward to Pixeldrain, date
        # directories preserved, emptied directories removed so the spool
        # returns to quiescent-empty. `move` deletes the local copy only
        # after Pixeldrain confirms -- the spool stays the durable hop.
        # No --min-age guard: nginx DAV writes to its own temp dir and
        # renames complete files in, so the spool never shows partials.
        camera-relay = {
          serviceConfig = {
            Type = "oneshot";
            # nginx owns the spool tree; running as the same user keeps
            # deletion rights without loosening the 0750 dirs.
            User = "nginx";
            Group = "nginx";
            EnvironmentFile = config.sops.templates."camera-relay.env".path;
            ExecStart = "${pkgs.rclone}/bin/rclone --config /dev/null move /var/spool/camera-ingest pixeldrain:camera --delete-empty-src-dirs";
            MemoryMax = "128M";
          };
        };
      };
      # A timer rather than a DirectoryNotEmpty path unit: a path unit
      # re-checks its condition every time the triggered service
      # deactivates, so any file it cannot relay (Pixeldrain outage) makes
      # it re-fire in a busy loop. A minutely timer retries calmly and the
      # extra latency is invisible for this use case.
      timers.camera-relay = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "1m";
        };
      };
      # Node-local spool, no Hetzner Volume (Disposable-adjacent: files
      # live here only between phone upload and relay pickup), so plain
      # tmpfiles is safe -- no volume mount to race against.
      tmpfiles.rules = ["d /var/spool/camera-ingest 0750 nginx nginx -"];
    };
  };
}
