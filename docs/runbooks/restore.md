# Runbook: restic restore

Restore one Legion service's backup set. Read [`AGENTS.md`](../../AGENTS.md)
first. Every command runs on the node that owns the service and asks for the
operator's sudo password, so use `ssh -t`.

## Where the backups are

- Bucket `legion-restic-backups` at `https://s3.eu-central-1.s4.mega.io`,
  created outside this flake with an application key scoped to it.
- One repository per service:
  `s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service>`.
- Secrets in `modules/nixos/backups/secrets.yaml`: `restic/password` (one
  repository password for all services) and `restic/s4-env` (an
  `AWS_ACCESS_KEY_ID=` line and an `AWS_SECRET_ACCESS_KEY=` line).
- Each node has a `restic-<service>` wrapper that already sets the
  repository, password file, and S4 credentials, so no secret leaves the node.
- The backed-up paths and the units a backup stops:

  ```sh
  nix eval --json .#nixosConfigurations.<node>.config.backups.jobs
  ```

## List snapshots

```sh
ssh -t <node>.jeiang.dev sudo restic-<service> snapshots
```

## Restore to a scratch directory

Never restore over live data first.

```sh
ssh -t <node>.jeiang.dev sudo restic-<service> restore <snapshot-id> --target /tmp/restore-<service>
```

## Verify

- Every path in the job's `paths` exists under `/tmp/restore-<service>`.
- Each SQLite database passes an integrity check:

  ```sh
  ssh -t <node>.jeiang.dev sudo nix shell nixpkgs#sqlite -c sqlite3 /tmp/restore-<service>/<path-to-db> 'PRAGMA integrity_check;'
  ```

- File counts and sizes are close to the live path.
- Delete the scratch copy when done:

  ```sh
  ssh -t <node>.jeiang.dev sudo rm -rf /tmp/restore-<service>
  ```

## Restore over the live path

Only after the scratch copy passes, and only to recover from data loss.

1. Stop every unit in the job's `pauseUnits`:

    ```sh
    ssh -t <node>.jeiang.dev sudo systemctl stop <pause-units>
    ```

2. Restore. `--delete` removes files that are not in the snapshot, inside the
    restored paths only:

    ```sh
    ssh -t <node>.jeiang.dev sudo restic-<service> restore <snapshot-id> --target / --overwrite always --delete
    ```

3. For garret, follow [`garret.md`](garret.md) before starting its units.
4. Start the units again and confirm the service answers:

    ```sh
    ssh -t <node>.jeiang.dev sudo systemctl start <pause-units>
    ```

## Retention

Each daily run keeps 30 daily snapshots (`--keep-daily 30` in
`modules/nixos/backups/default.nix`). Older snapshots are gone.
