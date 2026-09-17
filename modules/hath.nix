{self, ...}: let
  dataDir = "/mnt/hath";
  port = 8888;
in {
  legion.services.hath = {
    node = "legion-node4";
    module = "hath";
    stateful = true;
    units = ["hath"];
    ports.app = port;
    firewall = [
      {
        inherit port;
        proto = "tcp";
        scope = "public";
      }
    ];
    volume = {
      name = "legion-hath";
      mountpoint = dataDir;
      hcloudVolumeId = "106251745";
      sizeGiB = 40;
    };
    backupSet = ["${dataDir}/data" "${dataDir}/cache"];
  };

  # No edge route: Caddy cannot proxy H@H's binary protocol.
  nixos.modules.hath = {
    lib,
    pkgs,
    ...
  }: let
    hathPkg = pkgs.hath-rust;
  in {
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
            (lib.getExe hathPkg)
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
