_: {
  # docs/MIGRATION.md piece 2.1: Restic backups to a dedicated Mega S4
  # bucket, driven entirely by the Legion inventory's per-service
  # `backupSet`/`backupPauseUnits` fields
  # (modules/hosts/legion/_service-inventory.nix). `netbird-server` (piece
  # 3.1) is the first service to declare `backupSet`; `backups.jobs` stays
  # empty on every other node until its own stateful service lands (Phases
  # 4-5), producing zero services.restic.backups entries there. Imported
  # unconditionally by
  # legionConfiguration (modules/hosts/legion/default.nix); never imported
  # on artemis (IMPROVEMENTS §1: Artemis gets its own backup allowlist as
  # separate future work).
  flake.nixosModules.backups = {
    config,
    lib,
    ...
  }: let
    cfg = config.backups;

    # Operator-provisioned bucket (external prerequisite, documented in
    # docs/runbooks/restore.md), dedicated to Restic state -- separate from
    # Attic's own "attic" Mega S4 bucket (k8s-manifests attic/values.yaml).
    # Region matches Attic's existing Mega S4 account (k8s-manifests
    # attic/README.md default eu-central-1) purely so there's one fewer
    # region to administer; not a requirement of the backup data itself.
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
        Per-service Restic backup jobs, keyed by service name
        (docs/MIGRATION.md piece 2.1). Populated per-host from the Legion
        inventory's backupSet/backupPauseUnits fields
        (modules/hosts/legion/default.nix); do not set by hand elsewhere.
      '';
    };

    config = lib.mkIf (cfg.jobs != {}) {
      # docs/runbooks/restore.md prerequisites: create both with
      # `just sops-edit` before a node with any backupSet entry deploys.
      # One shared repository password (reused across every service's
      # independent repository below -- restic doesn't require per-repo
      # passwords to differ) and one shared S3 credential env file
      # (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for the Mega S4 access
      # key scoped to the bucket above).
      sops.secrets = {
        "restic/password" = {};
        "restic/s4-env" = {};
      };

      services.restic.backups =
        lib.mapAttrs (name: job: {
          inherit (job) paths;
          # Layout: s3:<endpoint>/<bucket>/<node>/<service> -- one
          # independent repository per service so a restore or prune on
          # one never touches another's snapshots.
          repository = "s3:${s4Endpoint}/${s4Bucket}/${config.networking.hostName}/${name}";
          passwordFile = config.sops.secrets."restic/password".path;
          environmentFile = config.sops.secrets."restic/s4-env".path;
          initialize = true;
          timerConfig = {
            OnCalendar = "daily";
            # Fleet-wide stagger (docs/MIGRATION.md piece 2.1): without
            # this every service on every node would fire at the same
            # instant.
            RandomizedDelaySec = "4h";
            Persistent = true;
          };
          pruneOpts = ["--keep-daily 30"]; # IMPROVEMENTS §1: 30-day retention
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
