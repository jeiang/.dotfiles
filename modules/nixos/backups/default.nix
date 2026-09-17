_: {
  flake.nixosModules.backups = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.backups;

    s4Endpoint = "https://s3.eu-central-1.s4.mega.io";
    s4Bucket = "legion-restic-backups";
    repositoryFor = name: "s3:${s4Endpoint}/${s4Bucket}/${config.networking.hostName}/${name}";

    jobType = lib.types.submodule {
      options = {
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            Explicit allowlist of paths to back up, inside the service's
            Volume mountpoint.
          '';
        };
        volume = lib.mkOption {
          type = lib.types.str;
          description = ''
            Mountpoint of the Volume the job's paths live on. Guards the
            backup against running while the Volume is not mounted.
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
      };
    };
  in {
    options.backups.jobs = lib.mkOption {
      type = lib.types.attrsOf jobType;
      default = {};
      description = ''
        Per-service Restic backup jobs, keyed by service name. Populated
        per-host from the Legion inventory's backupSet/backupPauseUnits
        fields (modules/hosts/legion/default.nix); do not set by hand
        elsewhere.
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
          # No forget/prune here: pruneOpts = [] makes the nixpkgs restic
          # module skip that step entirely, so pruning never runs while
          # job.pauseUnits are stopped. restic-maintenance-<name> below
          # prunes and checks on its own weekly schedule instead.
          pruneOpts = [];
          extraBackupArgs = ["--retry-lock" "2h"];
          backupPrepareCommand =
            ''
              ${pkgs.util-linux}/bin/mountpoint -q ${job.volume} || { echo "restic-backups-${name}: ${job.volume} is not mounted, refusing to back up an empty directory" >&2; exit 1; }
            ''
            + lib.optionalString (job.pauseUnits != []) ''
              systemctl stop ${lib.concatStringsSep " " job.pauseUnits}
            '';
          backupCleanupCommand = lib.optionalString (job.pauseUnits != []) ''
            systemctl start ${lib.concatStringsSep " " job.pauseUnits}
          '';
        })
        cfg.jobs;

      systemd.services =
        lib.mapAttrs' (name: job:
          lib.nameValuePair "restic-backups-${name}" {
            unitConfig.RequiresMountsFor = [job.volume];
          })
        cfg.jobs
        // lib.mapAttrs' (name: _job:
          lib.nameValuePair "restic-maintenance-${name}" {
            description = "Restic prune and integrity check for ${name}";
            # Ordered after the backup unit (not just network-online.target)
            # so a Persistent=true catch-up at boot runs the daily backup
            # first instead of the two units racing for the repository lock.
            after = ["network-online.target" "restic-backups-${name}.service"];
            wants = ["network-online.target"];
            environment = {
              RESTIC_CACHE_DIR = "/var/cache/restic-backups-${name}";
              RESTIC_PASSWORD_FILE = config.sops.secrets."restic/password".path;
              RESTIC_REPOSITORY = repositoryFor name;
            };
            serviceConfig = {
              Type = "oneshot";
              EnvironmentFile = config.sops.secrets."restic/s4-env".path;
              ExecStart = [
                "${lib.getExe pkgs.restic} forget --retry-lock 2h --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6"
                "${lib.getExe pkgs.restic} check --retry-lock 2h --read-data-subset=5%"
              ];
            };
          })
        cfg.jobs;

      systemd.timers = lib.mapAttrs' (name: _:
        lib.nameValuePair "restic-maintenance-${name}" {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "weekly";
            RandomizedDelaySec = "12h";
            Persistent = true;
          };
        })
      cfg.jobs;
    };
  };
}
