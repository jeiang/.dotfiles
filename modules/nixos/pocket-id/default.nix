{self, ...}: {
  flake.nixosModules.pocket-id = {
    config,
    pkgs,
    ...
  }: let
    # The unit runs WorkingDirectory=dataDir, so the app's relative default
    # paths resolve to ${dataDir}/data/*.
    dataDir = "/mnt/pocket-id";
    sopsFile = ./secrets.yaml;
  in {
    services.pocket-id = {
      enable = true;
      inherit dataDir;
      settings = {
        APP_URL = "https://auth.jeiang.dev";
        TRUST_PROXY = true;
      };
      # SMTP is DB-backed and admin-UI configured in the pinned Pocket ID
      # version; there is nothing to wire here.
      environmentFile = config.sops.templates."pocket-id.env".path;
    };

    systemd.services.pocket-id =
      {
        serviceConfig = {
          MemoryMax = "256M";
          # The module's tmpfiles rule for dataDir is not ordered after the
          # Volume mount; re-assert ownership here since ExecStartPre
          # inherits RequiresMountsFor (mountGuard). `+` runs it as root.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o pocket-id -g pocket-id -m 0755 ${dataDir}";
        };
      }
      // self.lib.mountGuard dataDir;

    sops = {
      secrets = {
        "pocket-id/encryption-key" = {inherit sopsFile;};
        "pocket-id/static-api-key" = {inherit sopsFile;};
      };
      templates."pocket-id.env" = {
        owner = config.services.pocket-id.user;
        # An EnvironmentFile is read once at start-up; without this a rotated
        # key never reaches the running process.
        restartUnits = ["pocket-id.service"];
        content = ''
          ENCRYPTION_KEY=${config.sops.placeholder."pocket-id/encryption-key"}
          STATIC_API_KEY=${config.sops.placeholder."pocket-id/static-api-key"}
        '';
      };
    };
  };
}
