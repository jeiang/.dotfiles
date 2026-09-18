_: let
  port = 8889;
  dataDir = "/var/lib/atuin";
  database = "${dataDir}/atuin.db";
in {
  legion.services.atuin = {
    node = "legion-node4";
    module = "atuin";
    stateful = true;
    units = ["atuin"];
    ports.app = port;
    # Mesh only: every client is a NetBird peer and that interface is
    # already trusted, so the server needs no firewall opening, no edge
    # vhost and no DNS record. The sync payload is end-to-end encrypted
    # under the client key either way.
    firewall = [];
    backupSet = [dataDir];
  };

  nixos.modules.atuin = {
    config,
    lib,
    pkgs,
    ...
  }: let
    job = config.services.restic.backups.atuin;

    restore = pkgs.writeShellScript "atuin-restore" ''
      set -euo pipefail

      if [ -e ${database} ]; then
        exit 0
      fi

      restic=${lib.getExe pkgs.restic}

      # First deploy: restic-backups-atuin initializes the repository.
      if ! "$restic" cat config >/dev/null 2>&1; then
        echo "atuin-restore: no repository yet, starting with an empty history"
        exit 0
      fi

      if [ "$("$restic" snapshots --latest 1 --json)" = "[]" ]; then
        echo "atuin-restore: repository holds no snapshot, starting with an empty history"
        exit 0
      fi

      "$restic" restore latest --target /
      ${pkgs.coreutils}/bin/chown -R atuin:atuin ${dataDir}
    '';
  in {
    users = {
      groups.atuin = {};
      users.atuin = {
        isSystemUser = true;
        group = "atuin";
      };
    };

    services.atuin = {
      enable = true;
      inherit port;
      host = "0.0.0.0";
      database = {
        createLocally = false;
        uri = "sqlite://${database}";
      };
    };

    systemd = {
      services = {
        atuin.serviceConfig = {
          # A static user keeps the database at /var/lib/atuin; DynamicUser
          # would move it into /var/lib/private, which restic would then
          # back up and restore under a path the service does not read.
          DynamicUser = lib.mkForce false;
          User = "atuin";
          Group = "atuin";
          StateDirectory = "atuin";
          MemoryMax = "128M";
        };

        atuin-restore = {
          description = "Restore the atuin history database from restic";
          requiredBy = ["atuin.service"];
          before = ["atuin.service"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          environment = {
            RESTIC_CACHE_DIR = "/var/cache/atuin-restore";
            RESTIC_PASSWORD_FILE = job.passwordFile;
            RESTIC_REPOSITORY = job.repository;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            CacheDirectory = "atuin-restore";
            EnvironmentFile = job.environmentFile;
            ExecStart = restore;
          };
        };
      };

      # The root disk holds the only live copy, so the snapshot interval is
      # the history that a lost node loses. An hour is the budget.
      timers.restic-backups-atuin.timerConfig = {
        OnCalendar = lib.mkForce "hourly";
        RandomizedDelaySec = lib.mkForce "5m";
      };
    };
  };
}
