_: let
  s4Endpoint = "https://s3.eu-central-1.s4.mega.io";
  retention = "--keep-daily 7 --keep-weekly 4 --keep-monthly 6";

  # Pruning gets its own unit and schedule: inside the backup unit it would
  # hold the repository lock for the whole backup window, and on Legion it
  # would run while a job's paused units are down.
  maintenanceService = {
    pkgs,
    lib,
    name,
    repository,
    passwordFile,
    environmentFile,
  }: {
    description = "Restic prune and integrity check for ${name}";
    # Ordered after the backup unit (not just network-online.target)
    # so a Persistent=true catch-up at boot runs the daily backup
    # first instead of the two units racing for the repository lock.
    after = ["network-online.target" "restic-backups-${name}.service"];
    wants = ["network-online.target"];
    environment = {
      RESTIC_CACHE_DIR = "/var/cache/restic-backups-${name}";
      RESTIC_PASSWORD_FILE = passwordFile;
      RESTIC_REPOSITORY = repository;
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = environmentFile;
      ExecStart = [
        "${lib.getExe pkgs.restic} forget --retry-lock 2h --prune ${retention}"
        # The ISO week picks one of 52 fixed slices, so every pack is read about once a year.
        (toString (pkgs.writeShellScript "restic-check-${name}" ''
          exec ${lib.getExe pkgs.restic} check --retry-lock 2h --read-data-subset="$((10#$(date +%V) % 52 + 1))/52"
        ''))
      ];
    };
  };

  maintenanceTimer = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "12h";
      Persistent = true;
    };
  };
in {
  nixos.modules.legion = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.backups;

    s4Bucket = "legion-restic-backups";
    repositoryFor = name: "s3:${s4Endpoint}/${s4Bucket}/${config.networking.hostName}/${name}";

    jobType = lib.types.submodule {
      options = {
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            Explicit allowlist of paths to back up, inside the service's
            Volume mountpoint when it has one.
          '';
        };
        volume = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Mountpoint of the Volume the job's paths live on. Guards the
            backup against running while the Volume is not mounted. Null
            for a service that keeps its state on the root disk, where the
            repository is the only copy of it.
          '';
        };
        pauseUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            systemd units to stop before the snapshot and start again after,
            so live SQLite databases are captured consistently.
          '';
        };
        schedule = {
          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "daily";
          };
          randomizedDelaySec = lib.mkOption {
            type = lib.types.str;
            default = "4h";
          };
        };
        prepareCommand = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Shell run before the snapshot, after the Volume check, such as
            an online copy of a live database into one of the paths.
          '';
        };
      };
    };
  in {
    options.backups.jobs = lib.mkOption {
      type = lib.types.attrsOf jobType;
      default = {};
      description = ''
        Per-service Restic backup jobs, keyed by service name. Legion nodes
        populate them from each `legion.services` entry's backupSet and
        units (modules/hosts/legion/default.nix); by default a backup
        pauses the service's own units.
      '';
    };

    config = lib.mkIf (cfg.jobs != {}) {
      # Create both with `just sops-edit` before a node with any backupSet
      # entry deploys.
      sops.secrets = let
        sopsFile = ./secrets.yaml;
      in {
        "restic/password" = {inherit sopsFile;};
        "restic/s4-env" = {inherit sopsFile;};
      };

      services.restic.backups =
        lib.mapAttrs (name: job: {
          inherit (job) paths;
          repository = repositoryFor name;
          passwordFile = config.sops.secrets."restic/password".path;
          environmentFile = config.sops.secrets."restic/s4-env".path;
          initialize = true;
          timerConfig = {
            OnCalendar = job.schedule.onCalendar;
            RandomizedDelaySec = job.schedule.randomizedDelaySec;
            Persistent = true;
          };
          # An empty list makes the nixpkgs module skip forget/prune here.
          pruneOpts = [];
          extraBackupArgs = ["--retry-lock" "2h"];
          backupPrepareCommand =
            lib.optionalString (job.volume != null) ''
              ${pkgs.util-linux}/bin/mountpoint -q ${job.volume} || { echo "restic-backups-${name}: ${job.volume} is not mounted, refusing to back up an empty directory" >&2; exit 1; }
            ''
            + lib.optionalString (job.pauseUnits != []) ''
              systemctl stop ${lib.concatStringsSep " " job.pauseUnits}
            ''
            + job.prepareCommand;
          backupCleanupCommand = lib.optionalString (job.pauseUnits != []) ''
            systemctl start ${lib.concatStringsSep " " job.pauseUnits}
          '';
        })
        cfg.jobs;

      systemd.services =
        lib.mapAttrs' (name: job:
          lib.nameValuePair "restic-backups-${name}" {
            unitConfig.RequiresMountsFor = lib.optional (job.volume != null) job.volume;
          })
        cfg.jobs
        // lib.mapAttrs' (name: _job:
          lib.nameValuePair "restic-maintenance-${name}" (maintenanceService {
            inherit lib name pkgs;
            repository = repositoryFor name;
            passwordFile = config.sops.secrets."restic/password".path;
            environmentFile = config.sops.secrets."restic/s4-env".path;
          }))
        cfg.jobs;

      systemd.timers = lib.mapAttrs' (name: _:
        lib.nameValuePair "restic-maintenance-${name}" maintenanceTimer)
      cfg.jobs;
    };
  };

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.backups.persist;

    repository = "s3:${s4Endpoint}/artemis-restic-backups/persist";
    btrfs = "${pkgs.btrfs-progs}/bin/btrfs";

    # A live path's place under /persist, found through the persistence entry
    # it is, lies inside, or contains; null when no entry covers it.
    storedPath = path: let
      covering = lib.filter (e: e.live == path || lib.hasPrefix "${e.live}/" path || lib.hasPrefix "${path}/" e.live) config.persistence.entries;
      roots = lib.unique (map (e: lib.removeSuffix e.live e.stored) covering);
    in
      if lib.length roots == 1
      then lib.removePrefix "/persist/" (lib.head roots + path)
      else null;
    inSnapshot = path: "${cfg.snapshot}/${toString (storedPath path)}";
    stopUnits = lib.concatStringsSep " " cfg.stopUnits;
  in {
    options.backups.persist = {
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Live paths backed up from /persist: each is a persistence.* path,
          lies inside one, or holds only persistence.* paths.
        '';
      };
      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Live paths inside `paths` left out of the backup.";
      };
      stopUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Units stopped while the read-only snapshot is taken.";
      };
      # Read-only btrfs snapshot of /persist that restic reads, so it never
      # reads a file while it is written.
      snapshot = lib.mkOption {
        type = lib.types.str;
        default = "/persist/.backup-snapshot";
        readOnly = true;
        internal = true;
      };
    };

    config = {
      # A path that is not persisted is empty after a reboot, and restic would
      # fail on it rather than quietly shrink the backup.
      assertions =
        map (path: {
          assertion = storedPath path != null;
          message = "backups: ${path} is not a persistence.* path";
        })
        (cfg.paths ++ cfg.exclude);

      # The backup-freshness alert reads the timers' last trigger.
      monitoredUnits = ["restic-backups-*.service" "restic-backups-*.timer" "restic-maintenance-*.service" "restic-maintenance-*.timer"];

      sops.secrets = let
        sopsFile = ./secrets.artemis.yaml;
      in {
        "restic/password" = {inherit sopsFile;};
        "restic/s4-env" = {inherit sopsFile;};
      };

      services.restic.backups.persist = {
        inherit repository;
        paths = map inSnapshot cfg.paths;
        exclude = map inSnapshot cfg.exclude;
        passwordFile = config.sops.secrets."restic/password".path;
        environmentFile = config.sops.secrets."restic/s4-env".path;
        initialize = true;
        timerConfig = {
          OnCalendar = "02/6:00";
          RandomizedDelaySec = "15m";
          Persistent = true;
        };
        pruneOpts = [];
        extraBackupArgs = ["--retry-lock" "2h"];
        # Both guards are for a run that was killed before its cleanup: the
        # snapshot outlives the unit, and deleting one that is not there would
        # fail the unit after a successful backup.
        backupPrepareCommand = ''
          set -eu
          if [ -e ${cfg.snapshot} ]; then
            ${btrfs} subvolume delete ${cfg.snapshot}
          fi
          systemctl stop ${stopUnits}
          ${btrfs} subvolume snapshot -r /persist ${cfg.snapshot}
          systemctl start ${stopUnits}
        '';
        backupCleanupCommand = ''
          # nixpkgs runs cleanup through ExecStopPost, including prepare/backup failures.
          systemctl start ${stopUnits}
          if [ -e ${cfg.snapshot} ]; then
            ${btrfs} subvolume delete ${cfg.snapshot}
          fi
        '';
      };

      systemd = {
        services = {
          restic-backups-persist.unitConfig.RequiresMountsFor = ["/persist"];
          restic-maintenance-persist = maintenanceService {
            inherit lib pkgs repository;
            name = "persist";
            passwordFile = config.sops.secrets."restic/password".path;
            environmentFile = config.sops.secrets."restic/s4-env".path;
          };
        };
        timers.restic-maintenance-persist = maintenanceTimer;
      };
    };
  };
}
