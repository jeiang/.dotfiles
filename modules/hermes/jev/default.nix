_: let
  # Jev hands Hermes a pre-built message on this deliver_only route; Hermes
  # relays it to Telegram without an agent turn. jev_alert_digest.py reuses
  # it too, once the alert-triage checkpoint lands.
  jevDigestRoute = "jev-digest";

  common = builtins.readFile ./jev_common.py;
  mailTriageSrc = common + "\n" + builtins.readFile ./jev_mail_triage.py;
in {
  nixos.modules.artemis = {
    lib,
    pkgs,
    config,
    ...
  }: let
    hermesCfg = config.services.hermes-agent;
    webhook = hermesCfg.settings.platforms.webhook.extra;
    envFile = config.sops.secrets."hermes/env".path;

    mailTriage = pkgs.writers.writePython3Bin "jev-mail-triage" {} mailTriageSrc;
  in {
    # Jev's judgments run in front of Hermes as plain systemd services, never
    # as a tool the model itself chooses (AGENTS.md).
    services.hermes-agent.settings.platforms.webhook.extra.routes."${jevDigestRoute}" = {
      deliver_only = true;
      deliver = "telegram";
      prompt = "{digest}";
    };

    systemd = {
      services.jev-mail-triage = {
        description = "Triage unseen iCloud mail with Jev";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [pkgs.himalaya];
        serviceConfig = {
          Type = "oneshot";
          User = hermesCfg.user;
          Group = hermesCfg.group;
          EnvironmentFile = envFile;
          Environment = [
            "HERMES_WEBHOOK_HOST=${webhook.host}"
            "HERMES_WEBHOOK_PORT=${toString webhook.port}"
            "HERMES_WEBHOOK_ROUTE_DIGEST=${jevDigestRoute}"
          ];
          ExecStart = lib.getExe mailTriage;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [hermesCfg.stateDir];
        };
      };

      timers.jev-mail-triage = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*:0/15";
          Persistent = true;
        };
      };
    };
  };
}
