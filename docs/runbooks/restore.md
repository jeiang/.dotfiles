# Runbook: Restic Restore

Operator runbook for restoring a Host-Native Service's Backup Set
(`modules/nixos/backups.nix`). Review [`AGENTS.md`](../../AGENTS.md) before
running any command here.

This runbook restores a single service's Backup Set from its Mega S4 Restic
repository. It does not cover provisioning the bucket itself.

## Prerequisites

### External: the Mega S4 bucket

`modules/nixos/backups.nix` targets a dedicated bucket, separate from
Attic's own `attic` bucket:

| Setting | Value |
| --- | --- |
| Endpoint | `https://s3.eu-central-1.s4.mega.io` |
| Bucket | `legion-restic-backups` |

Create this bucket and an S3 application key scoped to it in the Mega S4
console before the first node with a `backupSet` entry deploys (provisioning
is outside this flake, per `DESIGN.md`).

### sops secrets

Create both with `just sops-edit` before the same deploy:

| Secret | Value |
| --- | --- |
| `restic/password` | A random repository encryption password (e.g. `openssl rand -hex 32`). Shared across every service's repository -- restic repositories don't need distinct passwords, and this keeps the secret surface small. |
| `restic/s4-env` | An env-file-shaped value: `AWS_ACCESS_KEY_ID=<key>` then `AWS_SECRET_ACCESS_KEY=<secret>` on the next line, for the Mega S4 application key above. |

### Repository layout

Each service gets its own independent repository:

```
s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service>
```

e.g. `.../legion-restic-backups/legion-node2/pocket-id`.

## List snapshots

Run on the node owning the service (its systemd units run as `root`, and
`RESTIC_PASSWORD_FILE`/S3 credentials are only readable there). Every
command below reads the credentials **inside** the SSH command, on the
remote node — not via local command substitution: the operator's
workstation doesn't have `/run/secrets/restic/s4-env`, and even where it
does (running this from a node itself), local substitution would leak the
decrypted secret into the local shell's environment/history instead of
staying on the node that's allowed to read it.

```sh
ssh <node>.jeiang.dev -- sudo systemctl cat restic-backups-<service>.service
ssh <node>.jeiang.dev -- sudo bash -lc '
  set -a; source /run/secrets/restic/s4-env; set +a
  RESTIC_PASSWORD_FILE=/run/secrets/restic/password \
    restic -r s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service> \
    snapshots
'
```

Confirm a recent snapshot exists (daily schedule, `modules/nixos/backups.nix`)
before proceeding.

## Restore to a scratch directory

Never restore directly over live data first. Pick the latest snapshot ID
from the listing above and restore it somewhere disposable:

```sh
ssh <node>.jeiang.dev -- sudo bash -lc '
  set -a; source /run/secrets/restic/s4-env; set +a
  RESTIC_PASSWORD_FILE=/run/secrets/restic/password \
    restic -r s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service> \
    restore <snapshot-id> --target /tmp/restic-restore-<service>
'
```

## Verify content

Required before trusting the backup for disaster recovery:

- Confirm every path from the service's `backupSet`
  (`modules/hosts/legion/_service-inventory.nix`) is present under
  `/tmp/restic-restore-<service>`.
- For a SQLite-backed service (Pocket ID, Actual Budget -- both declare
  `backupPauseUnits` so the snapshot is taken with the service stopped),
  confirm the database opens cleanly:
  ```sh
  sqlite3 /tmp/restic-restore-<service>/<path-to-db> "PRAGMA integrity_check;"
  ```
- Compare file sizes/counts against the live path as a sanity check that
  the snapshot isn't truncated or empty.
- Clean up the scratch directory once satisfied:
  `sudo rm -rf /tmp/restic-restore-<service>`.

## Restore to the live path (service stopped)

Only after scratch-directory verification passes, and only when actually
recovering from data loss:

```sh
ssh <node>.jeiang.dev -- sudo systemctl stop <service>.service
ssh <node>.jeiang.dev -- sudo bash -lc '
  set -a; source /run/secrets/restic/s4-env; set +a
  RESTIC_PASSWORD_FILE=/run/secrets/restic/password \
    restic -r s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service> \
    restore <snapshot-id> --target / --overwrite always
'
ssh <node>.jeiang.dev -- sudo systemctl start <service>.service
```

Confirm the service starts cleanly and serves traffic before considering
the restore complete.

## Retention

`--keep-daily 30` (`modules/nixos/backups.nix`): each daily backup run
prunes snapshots older than 30 daily generations. A snapshot ID from more
than 30 days ago will not be listed.
