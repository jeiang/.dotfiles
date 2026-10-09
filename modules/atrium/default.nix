_: let
  icloudAppleId = "aidan@aidanpinard.co";
  stateDirName = "atrium";
  stateDir = "/var/lib/${stateDirName}";
  atriumId = 880;
in {
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    envFile = config.sops.secrets."atrium/env".path;
    xdgConfigHome = "${stateDir}/config";
    himalayaConfig = "${xdgConfigHome}/himalaya/config.toml";
    vdirsyncerDir = "${stateDir}/vdirsyncer";
    calendarDir = "${vdirsyncerDir}/calendars";
    contactsDir = "${vdirsyncerDir}/contacts";
    vdirsyncerStatusDir = "${vdirsyncerDir}/status";

    mailTriage = pkgs.writers.writePython3Bin "atrium-mail-triage" {flakeIgnore = ["E501"];} (builtins.readFile ./mail_triage.py);

    himalayaTemplate = pkgs.writeText "atrium-himalaya-config" ''
      [accounts.icloud]
      default = true
      email = "${icloudAppleId}"
      display-name = "Aidan Pinard"

      [accounts.icloud.imap]
      server = "imap.mail.me.com:993"
      tls = {}

      [accounts.icloud.imap.sasl.plain]
      username = "''${ICLOUD_MAIL_USERNAME}"
      password.cmd = "printenv ICLOUD_APP_PASSWORD"
    '';

    renderHimalayaConfig = pkgs.writeShellScript "atrium-render-himalaya-config" ''
      set -euo pipefail
      install -d -m 0700 ${builtins.dirOf himalayaConfig}
      ${pkgs.gettext}/bin/envsubst '$ICLOUD_MAIL_USERNAME' < ${himalayaTemplate} > ${himalayaConfig}
      chmod 0600 ${himalayaConfig}
    '';

    vdirsyncerConfig = pkgs.writeText "atrium-vdirsyncer-config" ''
      [general]
      status_path = "${vdirsyncerStatusDir}"

      [pair icloud_calendar]
      a = "icloud_calendar_local"
      b = "icloud_calendar_remote"
      collections = ["from b"]

      [storage icloud_calendar_local]
      type = "filesystem"
      path = "${calendarDir}"
      fileext = ".ics"

      [storage icloud_calendar_remote]
      type = "caldav"
      url = "https://caldav.icloud.com/"
      username = "${icloudAppleId}"
      password.fetch = ["command", "printenv", "ICLOUD_APP_PASSWORD"]
      item_types = ["VEVENT"]

      [pair icloud_contacts]
      a = "icloud_contacts_local"
      b = "icloud_contacts_remote"
      collections = ["from b"]

      [storage icloud_contacts_local]
      type = "filesystem"
      path = "${contactsDir}"
      fileext = ".vcf"

      [storage icloud_contacts_remote]
      type = "carddav"
      url = "https://contacts.icloud.com/"
      username = "${icloudAppleId}"
      password.fetch = ["command", "printenv", "ICLOUD_APP_PASSWORD"]
      read_only = true
    '';

    hardening = {
      User = "atrium";
      Group = "atrium";
      StateDirectory = stateDirName;
      StateDirectoryMode = "0750";
      EnvironmentFile = envFile;
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
  in {
    users.users.atrium = {
      isSystemUser = true;
      uid = atriumId;
      group = "atrium";
    };
    users.groups.atrium.gid = atriumId;

    persistence.directories = [
      {
        directory = stateDir;
        user = "atrium";
        group = "atrium";
        mode = "0750";
      }
    ];

    sops.secrets."atrium/env" = {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["atrium-mail-triage.service" "atrium-vdirsyncer-sync.service"];
    };

    systemd = {
      services = {
        atrium-mail-triage = {
          description = "Triage unseen iCloud mail with Jev";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.himalaya];
          environment.XDG_CONFIG_HOME = xdgConfigHome;
          serviceConfig =
            hardening
            // {
              Type = "oneshot";
              ExecStartPre = renderHimalayaConfig;
              ExecStart = lib.getExe mailTriage;
            };
        };

        atrium-vdirsyncer-sync = {
          description = "Sync iCloud calendar and contacts via vdirsyncer";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.vdirsyncer];
          environment.VDIRSYNCER_CONFIG = vdirsyncerConfig;
          serviceConfig =
            hardening
            // {
              Type = "oneshot";
            };
          script = ''
            set -euo pipefail

            install -d -m 0700 "${calendarDir}" "${contactsDir}" "${vdirsyncerStatusDir}"

            # discover prompts on stdin for each new remote collection and has
            # no --yes flag; a bounded y-feed (not `yes |`, which would
            # SIGPIPE under pipefail) keeps it non-interactive.
            printf 'y\n%.0s' $(seq 1 100) | vdirsyncer discover
            vdirsyncer sync
          '';
        };
      };

      timers = {
        atrium-mail-triage = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*:0/15";
            Persistent = true;
          };
        };

        atrium-vdirsyncer-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "1m";
            OnUnitActiveSec = "15m";
          };
        };
      };
    };
  };
}
