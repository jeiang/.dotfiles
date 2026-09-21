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
        UI_CONFIG_DISABLED = true;
        ALLOW_USER_SIGNUPS = "withToken";
        SIGNUP_DEFAULT_USER_GROUP_IDS = builtins.toJSON [
          "88b3805f-275a-4f55-b3a9-d31d918d2ac3"
          "b652bdf8-f4c7-4c25-9552-7d93912fec40"
        ];
        EMAIL_VERIFICATION_ENABLED = true;
        EMAIL_LOGIN_NOTIFICATION_ENABLED = true;
        EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED = true;
        EMAIL_API_KEY_EXPIRATION_ENABLED = true;
        SMTP_HOST = "smtp.mail.me.com";
        SMTP_PORT = 587;
        SMTP_TLS = "starttls";
        SMTP_FROM = "noreply@jeiang.dev";
        SMTP_USER = "jeiang";
      };
      credentials.SMTP_PASSWORD = config.sops.secrets."pocket-id/smtp-password".path;
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
        "pocket-id/smtp-password" = {
          inherit sopsFile;
          restartUnits = ["pocket-id.service"];
        };
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
