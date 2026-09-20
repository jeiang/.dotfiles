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

  # Two blank lines between common's last def and the per-script body, so
  # flake8's E305 (blank lines after a function/class) doesn't fire at the
  # concatenation seam.
  common = builtins.readFile ./jev_common.py;
  mailTriageSrc = common + "\n\n" + builtins.readFile ./jev_mail_triage.py;
  alertTriageSrc = common + "\n\n" + builtins.readFile ./jev_alert_triage.py;
  alertDigestSrc = common + "\n\n" + builtins.readFile ./jev_alert_digest.py;
  memoryGateSrc = common + "\n\n" + builtins.readFile ./jev_memory_gate.py;
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
    # Matches modules/hermes/default.nix's himalayaConfigDir/config.toml; not
    # exported there, so the path is redefined here from the same stateDir.
    himalayaConfigFile = "${hermesCfg.stateDir}/.config/himalaya/config.toml";

    # flakeIgnore silences flake8 E501 (the scripts' long lines -- webhook
    # payload literals, error strings -- read better unwrapped than reflowed)
    # and E402: each script's own imports land after jev_common.py's
    # function defs at the concatenation seam, which pycodestyle reads as a
    # late import even though it is the true top of that script's own code.
    pyWriterArgs = {flakeIgnore = ["E501" "E402"];};
    mailTriage = pkgs.writers.writePython3Bin "jev-mail-triage" pyWriterArgs mailTriageSrc;
    alertTriage = pkgs.writers.writePython3Bin "jev-alert-triage" pyWriterArgs alertTriageSrc;
    alertDigest = pkgs.writers.writePython3Bin "jev-alert-digest" pyWriterArgs alertDigestSrc;
    memoryGate = pkgs.writers.writePython3Bin "jev-memory-gate" pyWriterArgs memoryGateSrc;

    # serviceConfig shared by both alert-triage units; STATE_DIRECTORY and
    # CREDENTIALS_DIRECTORY are set automatically by systemd from
    # StateDirectory/LoadCredential. User/Group pin the DynamicUser identity
    # so both units resolve to the same UID: without it each unit's dynamic
    # user is derived from its own unit name, and systemd re-chowns the
    # shared StateDirectory to whichever unit started most recently, breaking
    # the other unit's access to digest.jsonl.
    alertServiceConfig = {
      DynamicUser = true;
      User = "jev-alert-triage";
      Group = "jev-alert-triage";
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
    # jev-mail-triage, jev-alert-triage and jev-alert-digest all read
    # hermes/env too; this list merges with modules/hermes/default.nix's
    # ["hermes-agent.service"] so a rotation restarts every reader.
    sops.secrets."hermes/env".restartUnits = [
      "jev-mail-triage.service"
      "jev-alert-triage.service"
      "jev-alert-digest.service"
    ];

    # digest.jsonl in jev-alert-triage's StateDirectory must survive a
    # reboot on artemis's impermanent root.
    persistence.directories = ["/var/lib/jev-alert-triage"];

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
          # Skipped (not failed) until himalaya is configured, so the timer
          # stays quiet rather than firing every 15 minutes against nothing.
          unitConfig.ConditionPathExists = himalayaConfigFile;
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
