{self, ...}: let
  # jev-alert-triage's own listener; distinct from hermesWebhookPort (8644) in
  # modules/hermes/default.nix. Not exposed there, so read back through
  # config.services.hermes-agent.settings below instead of duplicating it.
  jevAlertPort = 8645;

  # Jev hands Hermes a pre-built message on this deliver_only route; Hermes
  # relays it to Telegram without an agent turn. jev_alert_digest.py reuses
  # the same route as jev_mail_triage.py.
  jevDigestRoute = "jev-digest";
  # jev-alert-page runs a real agent turn (the investigate-only prompt), so
  # it is not deliver_only.
  jevAlertPageRoute = "jev-alert-page";

  common = builtins.readFile ./jev_common.py;
  mailTriageSrc = common + "\n" + builtins.readFile ./jev_mail_triage.py;
  alertTriageSrc = common + "\n" + builtins.readFile ./jev_alert_triage.py;
  alertDigestSrc = common + "\n" + builtins.readFile ./jev_alert_digest.py;
  memoryGateSrc = common + "\n" + builtins.readFile ./jev_memory_gate.py;
in {
  flake.lib.jevAlertPort = jevAlertPort;

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
    alertTriage = pkgs.writers.writePython3Bin "jev-alert-triage" {} alertTriageSrc;
    alertDigest = pkgs.writers.writePython3Bin "jev-alert-digest" {} alertDigestSrc;
    memoryGate = pkgs.writers.writePython3Bin "jev-memory-gate" {} memoryGateSrc;

    # serviceConfig shared by both alert-triage units; STATE_DIRECTORY and
    # CREDENTIALS_DIRECTORY are set automatically by systemd from
    # StateDirectory/LoadCredential.
    alertServiceConfig = {
      DynamicUser = true;
      LoadCredential = ["hermes-env:${envFile}"];
      StateDirectory = "jev-alert-triage";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };
    alertEnvironment = [
      "HERMES_WEBHOOK_HOST=${webhook.host}"
      "HERMES_WEBHOOK_PORT=${toString webhook.port}"
      "HERMES_WEBHOOK_ROUTE_DIGEST=${jevDigestRoute}"
      "HERMES_WEBHOOK_ROUTE_ALERT_PAGE=${jevAlertPageRoute}"
    ];
  in {
    # Jev's judgments run in front of Hermes as plain systemd services and a
    # hook script, never as a tool the model itself chooses (AGENTS.md).
    services.hermes-agent.settings = {
      hooks_auto_accept = true; # non-interactive service account; nothing to prompt.
      hooks.pre_tool_call = [
        {
          matcher = "memory|fact_store";
          command = lib.getExe memoryGate;
          timeout = 20;
        }
      ];
      platforms.webhook.extra.routes = {
        "${jevDigestRoute}" = {
          deliver_only = true;
          deliver = "telegram";
          prompt = "{digest}";
        };
        "${jevAlertPageRoute}" = {
          deliver = "telegram";
          prompt = "{prompt}";
        };
      };
    };

    systemd = {
      services = {
        jev-mail-triage = {
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

        jev-alert-triage = {
          description = "Judge Alertmanager alerts with Jev before paging Hermes";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig =
            alertServiceConfig
            // {
              Restart = "on-failure";
              RestartSec = 5;
              ExecStart = lib.getExe alertTriage;
              Environment =
                alertEnvironment
                ++ [
                  "JEV_ALERT_BIND_HOST=${self.lib.netbirdPeers.artemis}"
                  "JEV_ALERT_BIND_PORT=${toString jevAlertPort}"
                  "JEV_ALERT_SOURCE_IP=${self.lib.netbirdPeers.legion-node3}"
                ];
            };
        };

        jev-alert-digest = {
          description = "Send the overnight Jev alert digest";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig =
            alertServiceConfig
            // {
              Type = "oneshot";
              ExecStart = lib.getExe alertDigest;
              Environment = alertEnvironment;
            };
        };
      };

      timers = {
        jev-mail-triage = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*:0/15";
            Persistent = true;
          };
        };

        jev-alert-digest = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*-*-* 08:00:00";
            Persistent = true;
          };
        };
      };
    };
  };
}
