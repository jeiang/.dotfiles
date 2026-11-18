# Decisions: Backups

Restic repositories, keys, and the second copy on artemis. These constrain changes; read [`AGENTS.md`](../../AGENTS.md) first.

- artemis and Legion back up to separate S4 buckets with separate keys, and
  one repository password covers all of Legion. A host that owns no backup
  job is therefore not a recipient of a backups shard, and adding one back
  means rotating the key it could read.
- Every repository has a second copy on artemis. After each successful
  backup, `restic-copy-<job>` copies the newest snapshot to a rest-server
  (`modules/backups/default.nix`) that stores it on the Mumei drive as
  `/mnt/Mumei/Backup/<host>/<job>`, and applies the same retention. The
  server has no authentication and is not append-only: the NetBird policies
  are the boundary. artemis never gets Legion's repository password, so it
  holds Legion data it cannot read. The drive is not always attached: the
  server starts only while it is mounted, and a missing drive fails the copy
  units, not the backups. zakkart backs up only `~/.omp`, and only there;
  nothing alerts when that backup fails.
