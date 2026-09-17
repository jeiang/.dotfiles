# Runbook: restic restore

Restore one Legion service's backup set, or artemis's `/persist` allowlist.
Read [`AGENTS.md`](../../AGENTS.md) first. Every Legion command runs on the
node that owns the service and asks for the operator's sudo password, so use
`ssh -t`. On artemis `doas` needs no password.

## Where the Legion backups are

- Bucket `legion-restic-backups` at `https://s3.eu-central-1.s4.mega.io`,
  created outside this flake with an application key scoped to it.
- One repository per service:
  `s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service>`.
- Secrets in `modules/backups/secrets.yaml`: `restic/password` (one
  repository password for all services) and `restic/s4-env` (an
  `AWS_ACCESS_KEY_ID=` line and an `AWS_SECRET_ACCESS_KEY=` line).
- Each node has a `restic-<service>` wrapper that already sets the
  repository, password file, and S4 credentials, so no secret leaves the node.
- The four sections below are the Legion procedure. artemis has its own.
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
  ssh -t <node>.jeiang.dev "sudo nix shell nixpkgs#sqlite -c sqlite3 /tmp/restore-<service>/<path-to-db> 'PRAGMA integrity_check;'"
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

2. Restore. Do not add `--delete`: with `--target /` it deletes everything on
    the node that is not in the snapshot.

    ```sh
    ssh -t <node>.jeiang.dev sudo restic-<service> restore <snapshot-id> --target / --overwrite always
    ```

3. Start the units again and confirm the service answers:

    ```sh
    ssh -t <node>.jeiang.dev sudo systemctl start <pause-units>
    ```

## artemis

artemis has one repository,
`s3:https://s3.eu-central-1.s4.mega.io/artemis-restic-backups/persist`, its
own bucket with an application key scoped to it, and its own
`restic/password` and `restic/s4-env` in
`modules/backups/secrets.artemis.yaml`. The wrapper is `restic-persist`.

Every path in a snapshot carries the `/persist/.backup-snapshot` prefix of
the btrfs snapshot it was read from, so a restore never writes straight back
over the live path. Restore, then copy:

```sh
ssh artemis.jeiang.vpn doas restic-persist snapshots
```

```sh
ssh artemis.jeiang.vpn doas restic-persist restore <snapshot-id> --target /tmp/restore-persist --include '/persist/.backup-snapshot/data/home/aidanp/.gnupg'
```

Check the copy, then put it back with `rsync -a` (`--delete` only when the
live directory must end up identical, and never with `/` as the target):

```sh
ssh artemis.jeiang.vpn doas rsync -a /tmp/restore-persist/persist/.backup-snapshot/data/home/aidanp/.gnupg/ /home/aidanp/.gnupg/
```

```sh
ssh artemis.jeiang.vpn doas rm -rf /tmp/restore-persist
```

`/persist/data/home/aidanp/...` and the path under `/home/aidanp` are the
same files: impermanence bind-mounts one onto the other. Writing to either
is the same write.

Rebuilding artemis from nothing reads the repository with the admin age key,
not with anything on the host. Restore `/persist/etc/ssh` first anyway: the
rebuilt host then decrypts every existing shard with its old key, instead of
needing new recipients in `.sops.yaml`.

## Retention

The daily `restic-backups-<service>` run only backs up; it keeps every
snapshot. A separate weekly `restic-maintenance-<service>` timer runs
`restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6`
followed by `restic check --read-data-subset=5%`, both defined in
`modules/backups/default.nix`. Snapshots outside that policy are gone
once a maintenance run has pruned them.

garret is not restored with restic; see
[`garret.md`](garret.md#recovering-a-lost-or-corrupt-index) for its cold-cache
recovery procedure.
