{
  inputs,
  self,
  ...
}: let
  port = 8470;
  stateDir = "/var/lib/f95-tracker";
  unit = "f95-tracker";
  oidc = {
    clientId = "e71a725c-6065-4119-9b4b-3ff567a28461";
    allowedSubjects = ["d677fcea-ce81-4fb5-bd24-79c3fb2990f2"];
  };
  secretNames = {
    oidcClientSecret = "f95-tracker/oidc-client-secret";
    sessionSecret = "f95-tracker/session-secret";
    ntfyToken = "f95-tracker/ntfy-token";
  };
in {
  legion.services.f95-tracker = {
    node = "peria";
    module = "f95-tracker";
    stateful = true;
    units = [unit];
    ports.app = port;
    firewall = [];
    backupSet = [stateDir];
  };

  nixos.modules.f95-tracker = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.f95-tracker.nixosModules.default];

    sops.secrets = lib.genAttrs (builtins.attrValues secretNames) (_: {
      sopsFile = ./secrets.yaml;
      restartUnits = ["${unit}.service"];
    });

    services.f95-tracker = {
      enable = true;
      host = "0.0.0.0";
      inherit port stateDir;
      baseUrl = "https://f95.proxy.jeiang.dev";
      oidc = {
        inherit (oidc) clientId allowedSubjects;
        issuer = "https://auth.jeiang.dev";
        clientSecretFile = config.sops.secrets.${secretNames.oidcClientSecret}.path;
      };
      sessionSecretFile = config.sops.secrets.${secretNames.sessionSecret}.path;
      ntfy = {
        url = self.lib.ntfyBaseUrl;
        topic = "f95-tracker";
        tokenFile = config.sops.secrets.${secretNames.ntfyToken}.path;
      };
    };

    backups.jobs.f95-tracker = {
      pauseUnits = [];
      prepareCommand = ''
        systemctl start ${config.services.f95-tracker.backupUnit}
      '';
    };

    systemd.timers.restic-backups-f95-tracker.timerConfig = {
      OnCalendar = lib.mkForce "hourly";
      RandomizedDelaySec = lib.mkForce "5m";
    };
  };
}
