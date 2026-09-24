# Runbook: garret (Nix binary cache)

Operator runbook for garret on legion-node4, the fleet's Nix binary cache.
Review [`AGENTS.md`](../../AGENTS.md) before running any command here.

garret is two units on one host:

| Unit | User | Port | Reached at | Auth |
| --- | --- | --- | --- | --- |
| `garret-puller.service` | `garret-puller` | 8081 | `cache.jeiang.dev` | Anonymous for narinfo/NAR; Pocket ID for the browse API |
| `garret-pusher.service` | `garret` | 8082 | `cache-push.jeiang.dev` | OIDC (GitHub Actions + Pocket ID) |

The Puller is in group `garret` only to share the database: `/mnt/garret` is
`garret:garret` 0750 and the database files are 0660. The signing key
(`garret`, 0400) and the admin socket (`garret`, 0600) are out of its reach.
Both units share one S3 key, which can write the bucket.

Metrics and `/healthz` are on separate listeners (9091 Pusher, 9092 Puller),
bound to legion-node4's private address and scraped by legion-node3.
legion-node3 also probes the Puller's `/ready/deep`, which fetches the first
byte of a real NAR through a presigned URL, so revoked S3 credentials or an
S4 outage fail it while `/ready` and the NAR redirects still look healthy.

Both hostnames must stay grey-clouded / DNS-only in Cloudflare.
`cache-push.jeiang.dev` is a hard requirement — a push is one streaming PUT
of a whole compressed NAR and Cloudflare rejects bodies over 100 MB on the
free plan, so a proxied push hostname 413s on any sizeable closure.
`cache.jeiang.dev` is a choice: NAR requests answer 302 to a presigned S3
URL, so proxying could only ever cache narinfo, while exposing the cache to
the shared-PoP ban behaviour that once made it unreachable from CI.

## Deploy

```bash
just deploy legion-node4 -s --remote-build
```

Then check both units and a real round-trip:

```bash
ssh node4.jeiang.dev 'bash -c "systemctl status garret-pusher garret-puller"'
```

```bash
curl -fsS https://cache.jeiang.dev/nix-cache-info
```

```bash
curl -fsS https://cache.jeiang.dev/ready/deep
```

A push is verified by the next `main` CI run, or manually:

```bash
nix run github:jeiang/garret#garret -- login
```

```bash
nix run github:jeiang/garret#garret -- push /nix/store/<some-path>
```

Both need a client config at `$XDG_CONFIG_HOME/garret/config.toml`; copy
`.ci/garret.toml` and set `oidc.client_id`/`oidc.audience` to the `garret`
Pocket ID client (the checked-in one is shaped for the GitHub Actions path,
which needs no login).

GitHub Actions tokens are accepted only from the workflows listed in
`job_workflow_refs` in `modules/garret/default.nix`, pinned by repository
id, on `push` and `workflow_dispatch`. A new repository or workflow that
pushes needs its entries there first.

## Operations

`garret-admin` is installed on legion-node4. It talks to the Pusher over its
admin socket at `/run/garret/admin.sock`, so it needs root and a running
Pusher; it never opens the database directly.

| Task | Command |
| --- | --- |
| Object count, usage vs quota, in-flight uploads | `ssh -t node4.jeiang.dev sudo garret-admin status` |
| Force a GC pass | `ssh -t node4.jeiang.dev sudo garret-admin gc run` |
| Backfill signatures after adding a key | `ssh -t node4.jeiang.dev sudo garret-admin resign` |
| Audit rows against blobs (dry run) | `ssh -t node4.jeiang.dev sudo garret-admin fsck --verify-sizes` |
| Take a database copy now | see [Backup](#backup) |

Quota is 250 GiB with eviction between the 0.95 and 0.85 watermarks
(`modules/garret/default.nix`).

### Pruning old closures

`prune` deletes every closure last pushed before a cutoff, keeping whatever
a newer push or a live pin still references. The cutoff is a UTC date or an
age, at least a day ago. Without `--apply` it only lists what would go:

```bash
ssh -t node4.jeiang.dev sudo garret-admin prune --before 90d
```

```bash
ssh -t node4.jeiang.dev sudo garret-admin prune --before 90d --apply
```

Negotiation and uploads pause while an applied prune runs.

### Deleting what one identity pushed

For a leaked or misused push identity, first revoke it (the GitHub issuer
allowlist in `modules/garret/default.nix`, or the Pocket ID client or user),
then list everything that subject first pushed. The subject is
`<issuer>#<sub>`, as the browse API's `pushed_by` shows it; `--since` takes a
UTC date or an age:

```bash
ssh -t node4.jeiang.dev "sudo garret-admin delete --pushed-by 'https://token.actions.githubusercontent.com#repo:jeiang/<repo>:ref:<ref>' --since 2d"
```

Add `--apply` to the same command to delete them. Unlike GC and `prune`,
`delete` is unconditional: it can remove paths other cached closures
reference, and those closures stay incomplete until they are pushed again.

### Key rotation

Generate the replacement (the key name is positional, not a flag), then read
back its public half:

```bash
nix run github:jeiang/garret#garret-admin -- key generate cache.jeiang.dev-2 ./key
```

```bash
nix run github:jeiang/garret#garret-admin -- key show ./key
```

`signingKeyFiles` is a list precisely so a rotation can overlap: add the new
key to `modules/garret/secrets.yaml` alongside the old, with the same
`owner = "garret"` and no `mode` or `group` (sops-nix's 0400), since a
group-readable key is one the Puller can read. Deploy, run
`garret-admin resign` to backfill signatures, add the new public key to every
consumer's `trusted-public-keys` (`modules/nix.nix`,
`.github/workflows/ci.yml`, `zakkart-bootstrap.md`), and only
then drop the old one from both places.

## Backup

The daily `restic-backups-garret` job does not stop garret. Its prepare step
removes `/mnt/garret/backup.db` and has the Pusher write a fresh consistent
copy there with `garret-admin backup` (SQLite `VACUUM INTO`, mode 0600),
and restic backs up only that file. The job fails if the Pusher is down. To
take a copy by hand, pick a new name inside `/mnt/garret` (the Pusher can
write nowhere else and never overwrites a file):

```bash
ssh -t node4.jeiang.dev sudo garret-admin backup /mnt/garret/manual-<date>.db
```

## Restoring the index

The copy is older than the bucket. Blobs evicted since it was taken still
have rows in it, and blobs uploaded since have none. `fsck --repair` drops
the first kind; the orphan sweep deletes the second and clients push them
again. That costs cache misses, never a broken closure, provided pushes stay
closed until fsck has covered every restored row. See garret's
`docs/spec/10-packaging.md` ("Backup and restore") for the reasoning.

1. Restore the copy to a scratch directory and check it
    ([`restore.md`](restore.md#restore-to-a-scratch-directory)). The file is
    `/tmp/restore-garret/mnt/garret/backup.db`.

2. Close the push endpoint. `enp7s0` is a trusted interface, so the NixOS
    firewall cannot do it; a separate table rejects the Pusher's port on
    every interface. A deploy leaves it in place, a reboot does not: do not
    reboot node4 before step 7, and if it reboots, repeat this step at once.

    ```bash
    ssh -t node4.jeiang.dev "sudo nft 'add table inet garret-restore; add chain inet garret-restore input { type filter hook input priority -10; }; add rule inet garret-restore input tcp dport 8082 reject with tcp reset'"
    ```

3. Stop both units:

    ```bash
    ssh -t node4.jeiang.dev sudo systemctl stop garret-puller garret-pusher
    ```

4. Put the copy in place, owned by `garret`, and delete the old WAL, which
    would otherwise be replayed over it:

    ```bash
    ssh -t node4.jeiang.dev "sudo bash -c 'install -o garret -g garret -m 0660 /tmp/restore-garret/mnt/garret/backup.db /mnt/garret/garret.db && rm -f /mnt/garret/garret.db-wal /mnt/garret/garret.db-shm'"
    ```

5. Start only the Pusher, then repair:

    ```bash
    ssh -t node4.jeiang.dev sudo systemctl start garret-pusher
    ```

    ```bash
    ssh -t node4.jeiang.dev sudo garret-admin fsck --repair --verify-sizes --quiesce
    ```

6. Start the Puller:

    ```bash
    ssh -t node4.jeiang.dev sudo systemctl start garret-puller
    ```

7. fsck skips rows younger than 24 hours, and no restored row is newer than
    the copy. From 24 hours after the snapshot time `restic-garret snapshots`
    showed, run the step 5 fsck again, then reopen pushes:

    ```bash
    ssh -t node4.jeiang.dev sudo nft delete table inet garret-restore
    ```

    CI pushes fail until then; its push steps are best-effort.

8. Re-apply any pins set or removed since the copy was taken, and delete
    the scratch directory.

### Cold cache

Without a usable copy, start from an empty cache:

1. Stop both units: `ssh -t node4.jeiang.dev sudo systemctl stop garret-puller garret-pusher`.
2. Empty the `garret` bucket.
3. Delete the database: `ssh -t node4.jeiang.dev sudo rm -f /mnt/garret/garret.db /mnt/garret/garret.db-wal /mnt/garret/garret.db-shm`.
4. Start both units again: `ssh -t node4.jeiang.dev sudo systemctl start garret-pusher garret-puller`.
5. Let CI push again on the next `main` run.
