# Runbook: garret (Nix binary cache)

Operator runbook for garret on legion-node4, the fleet's Nix binary cache
([ADR 0013](../adr/0013-replace-attic-with-garret.md)). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here.

garret is two units on one host:

| Unit | Port | Reached at | Auth |
| --- | --- | --- | --- |
| `garret-puller.service` | 8081 | `cache.jeiang.dev` | Anonymous for narinfo/NAR; Pocket ID for the browse API |
| `garret-pusher.service` | 8082 | `cache-push.jeiang.dev` | OIDC (GitHub Actions + Pocket ID) |

Metrics and `/healthz` are on separate listeners (9091 Pusher, 9092 Puller),
bound to legion-node4's private address and scraped by legion-node3.

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

## Operations

`garret-admin` talks to the Pusher over a root-only unix socket at
`/run/garret/admin.sock`; it never opens the database directly while the
Pusher is running.

| Task | Command (on legion-node4, as root) |
| --- | --- |
| Object count, usage vs quota, in-flight uploads | `garret-admin status` |
| Force a GC pass | `garret-admin gc run` |
| Backfill signatures after adding a key | `garret-admin resign` |

Quota is 250 GiB with eviction between the 0.95 and 0.85 watermarks
(`modules/nixos/garret/default.nix`).

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
key to `modules/nixos/garret/secrets.yaml` alongside the old, deploy, run
`garret-admin resign` to backfill signatures, add the new public key to every
consumer's `trusted-public-keys` (`modules/nixos/nix.nix`,
`modules/darwin/nix.nix`, both workflows, `zakkart-bootstrap.md`), and only
then drop the old one from both places.

### Losing the SQLite index

`/mnt/garret/garret.db` is the only record of what the bucket contains —
losing it strands every stored object as an orphan GC cannot reclaim. That
is why the Volume is backed up (`restic-backups-garret.service`). Restore it
per [`restore.md`](restore.md) with both units stopped.

If the index is genuinely unrecoverable, the cheapest fix is to empty the
`garret` bucket and let CI re-push, rather than leave orphans accruing
storage cost.
