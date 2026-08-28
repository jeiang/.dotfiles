{self, ...}: {
  # No edge route: Caddy cannot proxy H@H's binary protocol.
  flake.nixosModules.hath = {
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    hathPkg = self.packages.${system}.hath-rust;

    dataDir = "/mnt/hath";
  in {
    users.groups.hath = {};
    users.users.hath = {
      isSystemUser = true;
      group = "hath";
    };

    systemd.services.hath =
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
            "--disable-ip-origin-check"
            "--enable-metrics"
          ];
          # tmpfiles is not ordered after the Volume mount; ExecStartPre
          # inherits RequiresMountsFor (mountGuard). `+` runs it as root.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o hath -g hath -m 0750 ${dataDir}";
          Restart = "on-failure";
          RestartSec = 5;
          User = "hath";
          Group = "hath";
          PrivateTmp = true;
          MemoryMax = "256M";
        };
      }
      // self.lib.mountGuard dataDir;
  };
}
