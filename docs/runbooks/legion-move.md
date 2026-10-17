# Runbook: move a stateful Legion service to another node

Moving a service is a placement edit (`legion.services.<name>.node`) plus a
state migration. Read [`AGENTS.md`](../../AGENTS.md) and
[`restore.md`](restore.md) first. `<old>` and `<new>` are node names,
`<service>` is the `legion.services` key, and `<units>` are its `units` with
`.service` appended.

Restic repositories are per node:
`s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<node>/<service>`.
After the move, the `restic-<service>` wrapper on `<new>` points at
`<new>/<service>`, which is empty, so the old snapshots are read by passing
the old repository with `-r`.

## Before merge

1. Change `.sops.yaml` so every shard the service reads, and
    `modules/backups/secrets.yaml`, has `<new>` as a recipient. Drop `<old>`
    only from the service's own shard, and from the backups shard only when
    `<old>` keeps no backup job. Run `just sops-updatekeys` and commit the
    re-keyed shards to the branch.
2. If the service has a public port on a Hetzner node, add it to the
    `legion` Cloud Firewall before deploying (`just hcloud-drift` shows the
    difference).

## Cut over

1. Take a final backup on `<old>`, then stop the service there:

    ```sh
    ssh -t <old>.svr.jeiang.dev sudo systemctl start restic-backups-<service>
    ```

    ```sh
    ssh -t <old>.svr.jeiang.dev sudo systemctl stop <units>
    ```

2. Merge and wait for CI. DNS changes apply on merge.

3. Deploy `<new>`. The service starts with empty state:

    ```sh
    just deploy <new> --skip-checks --remote-build
    ```

4. Stop it on `<new>` and restore the old snapshot to a scratch directory:

    ```sh
    ssh -t <new>.svr.jeiang.dev sudo systemctl stop <units>
    ```

    ```sh
    ssh -t <new>.svr.jeiang.dev sudo restic-<service> -r s3:https://s3.eu-central-1.s4.mega.io/legion-restic-backups/<old>/<service> restore latest --target /tmp/restore-<service>
    ```

5. Verify the copy ([`restore.md`](restore.md#verify)), then put it in place.
    The snapshot holds the old paths; copy each `backupSet` path to the path
    the service uses on `<new>`, owned by the service's user. A `DynamicUser`
    service (state under `/var/lib/private`) needs no `chown`: systemd fixes
    the owner of its `StateDirectory` at start.

    ```sh
    ssh -t <new>.svr.jeiang.dev "sudo rsync -a --delete /tmp/restore-<service>/<old-path>/ <new-path>/ && sudo chown -R <user>:<group> <new-path>"
    ```

    garret's snapshot is an online database copy, not the live files: put it
    in place with steps 2 to 7 of
    [`garret.md`](garret.md#restoring-the-index). A snapshot taken on peria
    holds it at `/tmp/restore-garret/mnt/garret/backup.db`.

6. Start the service and check it answers, then delete the scratch copy:

    ```sh
    ssh -t <new>.svr.jeiang.dev sudo systemctl start <units>
    ```

    ```sh
    ssh -t <new>.svr.jeiang.dev sudo rm -rf /tmp/restore-<service>
    ```

7. Deploy `<old>` to remove the service there, and confirm the first
    `restic-backups-<service>` run on `<new>` succeeds.

## After

- A Hetzner Volume the service used on `<old>` is no longer mounted. Delete
  it in Hetzner once the new node has a good backup.
- The `<old>/<service>` repository is no longer pruned. Delete it from the
  bucket when its snapshots are no longer needed.
