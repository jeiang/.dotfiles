{self, ...}: let
  dataDir = "/mnt/hath";
  port = 8888;
in {
  # H@H serves /metrics on the same TLS-wrapped listener as the client
  # itself; its hath.network cert has no SAN for this IP, hence
  # insecure_skip_verify (transport trust is the private network).
  monitoring.scrape.hath = {
    type = "hath";
    targets = self.lib.monitoringTargets "hath" "app" "";
    settings = {
      scheme = "https";
      tls_config.insecure_skip_verify = true;
    };
  };

  legion.services.hath = {
    node = "peria";
    module = "hath";
    stateful = true;
    units = ["hath"];
    ports.app = port;
    publicPorts = [
      {
        inherit port;
        proto = "tcp";
      }
    ];
    volume = {
      name = "legion-hath";
      mountpoint = dataDir;
      hcloudVolumeId = "106251745";
      sizeGiB = 30;
    };
    backupSet = ["${dataDir}/data" "${dataDir}/cache"];
  };

  # No edge route: Caddy cannot proxy H@H's binary protocol.
  nixos.modules.hath = {
    lib,
    pkgs,
    ...
  }: {
    users.groups.hath = {};
    users.users.hath = {
      isSystemUser = true;
      group = "hath";
    };

    systemd.services.hath =
      lib.recursiveUpdate
      {
        description = "Hentai@Home client (hath-rust)";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.hath-rust)
            "--port"
            (toString port)
            "--cache-dir"
            "${dataDir}/cache"
            "--data-dir"
            "${dataDir}/data"
            "--download-dir"
            "${dataDir}/download"
            "--log-dir"
            "${dataDir}/log"
            "--temp-dir"
            "/tmp"
            "--enable-metrics"
          ];
          Restart = "on-failure";
          RestartSec = 5;
          User = "hath";
          Group = "hath";
          PrivateTmp = true;
          # A public-facing third-party binary: it may write only its Volume.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [dataDir];
          ProtectHome = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          MemoryMax = "256M";
        };
      }
      (self.lib.mountGuard dataDir {
        inherit pkgs;
        owner = "hath";
        mode = "0750";
      });
  };
}
