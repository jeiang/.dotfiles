# Hermes State Layout Migration

This runbook migrates `legion-node3` from the single `/mnt/hermes` tree to the
P10 runtime, cache, IPC, workspace, and durable paths. It does not authorize a
deployment or deletion. Obtain explicit approval immediately before stopping
the live services and again before deploying the D10 pin.

The migration is fail-closed. The P10 state initializer requires
`/mnt/hermes/durable/.layout-v1` with exact content
`hermes-p10-path-layout-v1`, owner `root:root`, and mode `0444`. Create that
marker only after every copy and verification below succeeds.

## 1. Preconditions

Confirm the active system is the expected D9 generation and that the old tree
is a real Hetzner Volume mount:

```console
readlink -f /run/current-system
findmnt -T /mnt/hermes -o TARGET,SOURCE,FSTYPE,OPTIONS
systemctl --failed
systemctl list-units 'hermes-*'
```

Resolve all pending requests and investigate every request in an `uncertain`
state. Do not migrate while a broker request, command, reminder, memory batch,
or calendar sync is running.

All destination roots must be absent. If any exists, stop and determine
whether a prior migration partially completed. Do not merge a new copy into
an old partial destination:

```console
sudo test ! -e /mnt/hermes/durable
sudo test ! -L /mnt/hermes/durable
sudo test ! -e /var/lib/hermes
sudo test ! -L /var/lib/hermes
sudo test ! -e /var/cache/hermes
sudo test ! -L /var/cache/hermes
sudo test ! -e /mnt/hermes/durable/.layout-v1
sudo test ! -L /mnt/hermes/durable/.layout-v1
```

## 2. Quiesce every writer

Stop the timers, sockets, and services before inspecting SQLite or copying
state:

```console
sudo systemctl stop \
  restic-backups-hermes.timer \
  restic-backups-hermes.service \
  hermes-memory-batch.timer \
  hermes-calendar-sync.timer \
  hermes-agent.service \
  hermes-approval-broker.service \
  hermes-approval-dispatcher.socket \
  hermes-approval-dispatcher.service \
  hermes-command-runner.socket \
  hermes-command-runner.service \
  hermes-reminder-runner.socket \
  hermes-reminder-runner.service \
  hermes-memory-batch.service \
  hermes-calendar-sync.service
systemctl is-active \
  restic-backups-hermes.timer \
  restic-backups-hermes.service \
  hermes-agent.service \
  hermes-approval-broker.service \
  hermes-approval-dispatcher.socket \
  hermes-command-runner.socket \
  hermes-reminder-runner.socket \
  hermes-memory-batch.timer \
  hermes-calendar-sync.timer
sudo lsof +D /mnt/hermes
```

Every `is-active` result must be `inactive`, and `lsof` must show no writer.
Leave the restic timer stopped until deployment and post-migration checks
finish.

Checkpoint and validate the upstream Hermes database while it is quiescent:

```console
sudo -u hermes sqlite3 /mnt/hermes/.hermes/state.db \
  'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;'
ls -l /mnt/hermes/.hermes/state.db*
```

The integrity result must be `ok`. If WAL or SHM sidecars remain, copy them
with the database. Never copy only `state.db`.

Create and verify the pre-migration backup only after every writer is stopped
and SQLite is checkpointed:

```console
sudo systemctl start restic-backups-hermes.service
systemctl status restic-backups-hermes.service
sudo restic snapshots --path /mnt/hermes
sudo restic check --read-data-subset=5%
```

Use the repository's configured restic environment when invoking `restic`
directly. Record the snapshot ID in the deployment log. Confirm the restic
service returned to `inactive`, and keep the timer and all Hermes writers
stopped.

## 3. Copy into the new layout

Reject unexpected symlinks before copying security-sensitive state:

```console
sudo find -P \
  /mnt/hermes/.hermes \
  /mnt/hermes/codex \
  /mnt/hermes/reminder-codex \
  /mnt/hermes/home \
  /mnt/hermes/calendar-sync \
  /mnt/hermes/.config \
  /mnt/hermes/publisher \
  /mnt/hermes/requests \
  /mnt/hermes/approval-status \
  /mnt/hermes/commands \
  /mnt/hermes/command-results \
  /mnt/hermes/reminders \
  /mnt/hermes/memory-batch \
  -type l -print
```

Omit absent optional sources from the inspection. Any output is a hard stop
until the link and its target are understood. P10 rejects symlinks anywhere
in durable state and in runtime credential, configuration, and database
paths. Worktrees are excluded from this blanket check because repositories
may legitimately contain symlinks. Then create the destination roots:

```console
sudo install -d -o root -g root -m 0751 \
  /mnt/hermes/durable \
  /var/lib/hermes \
  /var/cache/hermes
sudo install -d -o hermes -g hermes-workspace -m 2770 \
  /var/lib/hermes/worktrees
```

Copy durable state without crossing filesystems with `mv`:

```console
sudo rsync -aHAX --numeric-ids \
  --exclude=/home --exclude=/gh --exclude=/actual \
  /mnt/hermes/publisher/ /mnt/hermes/durable/broker/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/requests \
  /mnt/hermes/approval-status \
  /mnt/hermes/commands \
  /mnt/hermes/command-results \
  /mnt/hermes/reminders \
  /mnt/hermes/memory-batch \
  /mnt/hermes/calendar \
  /mnt/hermes/durable/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/.hermes/cron/ /mnt/hermes/durable/cron/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/publisher/actual/ /mnt/hermes/durable/actual/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/worktrees/knowledge-base-memory/memories/hermes/ \
  /mnt/hermes/durable/memory/
```

Omit a source that is disabled and absent, such as `calendar` or `actual`.
The durable memory directory must contain regular `MEMORY.md` and `USER.md`
files, not symlinks.

Copy local runtime state. The Hermes database and any WAL/SHM sidecars remain
together under `/var/lib/hermes/.hermes`:

```console
sudo rsync -aHAX --numeric-ids \
  --exclude=/cron --exclude=/memories --exclude=/cache \
  /mnt/hermes/.hermes/ /var/lib/hermes/.hermes/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/codex \
  /mnt/hermes/reminder-codex \
  /mnt/hermes/home \
  /mnt/hermes/calendar-sync \
  /mnt/hermes/.config \
  /var/lib/hermes/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/publisher/home \
  /mnt/hermes/publisher/gh \
  /var/lib/hermes/publisher/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/worktrees/ /var/lib/hermes/worktrees/
sudo rsync -aHAX --numeric-ids \
  /mnt/hermes/.gitconfig /var/lib/hermes/.gitconfig
```

Omit absent optional sources. Do not copy `/mnt/hermes/mirrors` or the old
Hermes cache. They are disposable and will be regenerated under
`/var/cache/hermes`.

## 4. Verify the copy and arm P10

Run checksum-only dry runs for each copy above. Each command must report no
file changes:

```console
sudo rsync -aHAXnci --numeric-ids SOURCE/ DESTINATION/
```

Inspect ownership, ACLs, and extended attributes:

```console
sudo getfacl -p /mnt/hermes/durable /var/lib/hermes /var/lib/hermes/worktrees
sudo getfattr -d -m- /mnt/hermes/durable /var/lib/hermes
sudo find /mnt/hermes/durable -xdev -type l -print
sudo du -sh /mnt/hermes/durable /var/lib/hermes /var/cache/hermes
```

Re-run SQLite integrity against the copied database:

```console
sudo -u hermes sqlite3 /var/lib/hermes/.hermes/state.db \
  'PRAGMA integrity_check;'
```

Flush the destination filesystems before arming the layout:

```console
sudo sync -f /mnt/hermes/durable
sudo sync -f /var/lib/hermes
sudo sync -f /var/cache/hermes
```

Only after all checks pass, create the fail-closed marker using a
same-directory atomic replacement:

```console
marker_tmp="$(sudo mktemp /mnt/hermes/durable/.layout-v1.XXXXXX)"
printf '%s\n' hermes-p10-path-layout-v1 |
  sudo tee "$marker_tmp" >/dev/null
sudo chown root:root "$marker_tmp"
sudo chmod 0444 "$marker_tmp"
sudo sync -f "$marker_tmp"
sudo mv -T "$marker_tmp" /mnt/hermes/durable/.layout-v1
sudo sync -f /mnt/hermes/durable
sudo test "$(cat /mnt/hermes/durable/.layout-v1)" = \
  hermes-p10-path-layout-v1
sudo test "$(stat -c '%U:%G:%a' /mnt/hermes/durable/.layout-v1)" = \
  root:root:444
```

## 5. Deploy and inspect

After a separate explicit deployment confirmation, deploy the D10 pin to
`legion-node3`. The state initializer must succeed before any Hermes socket,
timer, or service can start.

Verify the paths from the host and relevant service namespaces:

```console
findmnt -T /mnt/hermes/durable
findmnt -T /var/lib/hermes
findmnt -T /var/cache/hermes
systemctl show hermes-agent.service \
  -p RequiresMountsFor -p ReadWritePaths -p ReadOnlyPaths -p BindPaths
systemctl show hermes-approval-broker.service \
  -p RequiresMountsFor -p ReadWritePaths -p ReadOnlyPaths -p BindPaths
systemctl show hermes-command-runner.service \
  -p RequiresMountsFor -p ReadWritePaths -p ReadOnlyPaths -p BindPaths
sudo nsenter -t "$(systemctl show -p MainPID --value hermes-agent)" -m \
  findmnt
```

Confirm:

- sockets exist only beneath `/run/hermes`;
- runtime SQLite, transcripts, Codex state, and worktrees use
  `/var/lib/hermes`;
- caches and mirrors use `/var/cache/hermes`;
- memory, cron, broker journal, grants, audit, outbox, request status,
  command results, reminders, Actual data, and calendar data use
  `/mnt/hermes/durable`;
- no service writes new state into legacy locations.

Run the Hermes smoke tests for Telegram streaming, broker MCP health, command
execution, a reminder list, memory visibility, calendar sync, and automatic
execution audit/notification. Reboot once and repeat the checks.

Run `restic-backups-hermes.service`, confirm every writer is paused during the
snapshot and only previously active units restart, then restore the latest
`/mnt/hermes/durable` snapshot into a temporary directory and compare it with
the live durable tree. The backup fails closed if
`/run/restic-backup-hermes-active-units` remains from an interrupted run.
Investigate the interrupted backup and the recorded units before removing
that root-owned state file.

## Rollback and retention

If activation or smoke testing fails, roll back to the D9 system generation.
Stop the P10 units first. The migration commands do not alter or delete the
legacy `/mnt/hermes` sources, so D9 can resume against the old layout. Record
any P10-only side effects before rollback and do not copy them backward
without a request-by-request review.

If P10 accepted any request or wrote durable state after cutover, rollback is
not data-loss-free. Keep both P10 and D9 services stopped until those records
are reconciled or choose a forward repair. Do not let both layouts accept
requests.

Retain the old state tree for at least 30 days. Deleting any legacy path is a
separate destructive action requiring explicit confirmation after the P11
soak and a verified restic restore.
