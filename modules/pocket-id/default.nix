{self, ...}: let
  # WorkingDirectory=dataDir, so the app's relative default paths resolve
  # to ${dataDir}/data/*.
  dataDir = "/mnt/pocket-id";
  appPort = 1411;
in {
  legion.services.pocket-id = {
    node = "legion-node2";
    module = "pocket-id";
    stateful = true;
    units = ["pocket-id"];
    ports.app = appPort;
    firewall = [
      {
        port = appPort;
        proto = "tcp";
        scope = "private";
      }
    ];
    volume = {
      name = "legion-pocket-id";
      mountpoint = dataDir;
      hcloudVolumeId = "106117410";
      sizeGiB = 10;
    };
    backupSet = [dataDir];
  };

  nixos.modules.pocket-id = {
    config,
    lib,
    pkgs,
    ...
  }: let
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
