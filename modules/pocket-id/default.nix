{self, ...}: {
  nixos.modules.pocket-id = {
    config,
    lib,
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
      lib.recursiveUpdate
      {
        serviceConfig.MemoryMax = "256M";
      }
      (self.lib.mountGuard dataDir {
        inherit pkgs;
        owner = "pocket-id";
        mode = "0755";
      });

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
