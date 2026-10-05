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
        "${lib.getExe pkgs.restic} check --retry-lock 2h --read-data-subset=5%"
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
            OnCalendar = "daily";
            RandomizedDelaySec = "4h";
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
    home = config.users.users.${config.preferences.user.name}.home;

    repository = "s3:${s4Endpoint}/artemis-restic-backups/persist";

    # Read-only snapshot, so restic never reads a file while it is written.
    # It sits inside /persist, which is already mounted, so the unit needs no
    # mount of its own.
    snapshot = "/persist/.backup-snapshot";
    btrfs = "${pkgs.btrfs-progs}/bin/btrfs";

    # Paths relative to /persist.
    backupSet =
      # Host identity: with these two a rebuilt artemis keeps its sops key and
      # its NetBird peer address, which the flake hardcodes.
      ["etc/ssh" "var/lib/netbird" "var/lib/hermes"]
      ++ map (directory: "data${home}/${directory}") [
        ".config/sunshine"
        ".gnupg"
        ".local/share/PrismLauncher"
        ".local/share/fish"
        ".password-store"
        ".renpy"
        ".ssh"
      ];

    entryPath = entry:
      if builtins.isString entry
      then entry
      else entry.directory or entry.file;
    persisted =
      map (entry: lib.removePrefix "/" (entryPath entry))
      (config.persistence.directories ++ config.persistence.files)
      ++ map (entry: "data${home}/${entryPath entry}")
      (config.persistence.data.directories ++ config.persistence.data.files);
  in {
    # A path that is not persisted is empty after a reboot, and restic would
    # fail on it rather than quietly shrink the backup.
    assertions =
      map (path: {
        assertion =
          lib.elem path persisted
          # Either a parent of persisted entries (/persist holds nothing else)
          # or a path inside one.
          || lib.any (lib.hasPrefix "${path}/") persisted
          || lib.any (entry: lib.hasPrefix "${entry}/" path) persisted;
        message = "backups: /persist/${path} is not a persistence.* path";
      })
      backupSet;

    sops.secrets = let
      sopsFile = ./secrets.artemis.yaml;
    in {
      "restic/password" = {inherit sopsFile;};
      "restic/s4-env" = {inherit sopsFile;};
    };

    services.restic.backups.persist = {
      inherit repository;
      paths = map (path: "${snapshot}/${path}") backupSet;
      passwordFile = config.sops.secrets."restic/password".path;
      environmentFile = config.sops.secrets."restic/s4-env".path;
      initialize = true;
      timerConfig = {
        # Ahead of bees at 03:00, which stalls disk I/O until 09:00.
        OnCalendar = "02:00";
        Persistent = true;
      };
      pruneOpts = [];
      extraBackupArgs = ["--retry-lock" "2h"];
      # Both guards are for a run that was killed before its cleanup: the
      # snapshot outlives the unit, and deleting one that is not there would
      # fail the unit after a successful backup.
      backupPrepareCommand = ''
        set -eu
        if [ -e ${snapshot} ]; then
          ${btrfs} subvolume delete ${snapshot}
        fi
        ${btrfs} subvolume snapshot -r /persist ${snapshot}
      '';
      backupCleanupCommand = ''
        if [ -e ${snapshot} ]; then
          ${btrfs} subvolume delete ${snapshot}
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
}
