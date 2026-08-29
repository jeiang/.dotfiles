_: {
  flake.nixosModules.backups = {
    config,
    lib,
    ...
  }: let
    cfg = config.backups;

    s4Endpoint = "https://s3.eu-central-1.s4.mega.io";
    s4Bucket = "legion-restic-backups";

    jobType = lib.types.submodule {
      options = {
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            Backup Set paths for this service (DESIGN.md State And Backup
            Boundaries: an explicit allowlist, subset of the service's
            declared Volume mountpoint -- enforced by
            _service-inventory.nix's backupSetViolations assert).
          '';
        };
        pauseUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            systemd units to stop before the snapshot and start again after
            (SQLite-safe snapshots for services with a live DB in their
            Backup Set, e.g. Pocket ID, Actual Budget). No-op when empty.
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
          repository = "s3:${s4Endpoint}/${s4Bucket}/${config.networking.hostName}/${name}";
          passwordFile = config.sops.secrets."restic/password".path;
          environmentFile = config.sops.secrets."restic/s4-env".path;
          initialize = true;
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "4h";
            Persistent = true;
          };
          pruneOpts = ["--keep-daily 30"];
          backupPrepareCommand = lib.optionalString (job.pauseUnits != []) ''
            systemctl stop ${lib.concatStringsSep " " job.pauseUnits}
          '';
          backupCleanupCommand = lib.optionalString (job.pauseUnits != []) ''
            systemctl start ${lib.concatStringsSep " " job.pauseUnits}
          '';
        })
        cfg.jobs;
    };
  };
}
