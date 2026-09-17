{self, ...}: {
  # No edge route: Caddy cannot proxy H@H's binary protocol.
  nixos.modules.hath = {
    lib,
    pkgs,
    ...
  }: let
    hathPkg = pkgs.hath-rust;

    dataDir = "/mnt/hath";
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
            "8888"
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
