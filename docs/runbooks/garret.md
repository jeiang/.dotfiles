# Runbook: garret (Nix binary cache)

Operator runbook for standing up garret on legion-node4 and running it
alongside Attic through the side-by-side window
([ADR 0013](../adr/0013-replace-attic-with-garret.md)). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here.

garret is two units on one host:

| Unit | Port | Reached at | Auth |
| --- | --- | --- | --- |
| `garret-puller.service` | 8081 | `cache.jeiang.dev` | Anonymous for narinfo/NAR; Pocket ID for the browse API |
| `garret-pusher.service` | 8082 | `cache-push.jeiang.dev` | OIDC (GitHub Actions + Pocket ID) |

Metrics and `/healthz` are on separate listeners (9091 Pusher, 9092 Puller),
bound to legion-node4's private address and scraped by legion-node3.

The Pusher is on 8082 rather than garret's upstream default of 8080 because
atticd holds 8080 on this node until it retires.

## Prerequisites

Every item below is external to this flake and must be done before
legion-node4 deploys. The branch does not evaluate until the sops shard
exists, and the module refuses to build while the Pocket ID audience is
still a placeholder.

### 1. Make `jeiang/garret` public

`flake.nix` fetches it with the plain `github:` fetcher. A private repo would
need an access token in CI, on the Mac, and on every node that evaluates.

### 2. MEGA S4 bucket

Create a bucket named `garret` at `https://s3.ca-montreal.megas4.com`
(region `ca-montreal`), separate from Attic's `attic` bucket and from
`legion-restic-backups`. Create an application key scoped to it.

### 3. Hetzner Volume

```bash
hcloud volume create --name legion-garret --size 10 --server legion-node4 --format ext4
```

Paste the numeric id into `modules/hosts/legion/_service-inventory.nix` as
`garret.volume.hcloudVolumeId`. Until it is set, no `fileSystems` entry and
no restic job is generated, and the units refuse to start (their mount guard
fails on an unmounted `/mnt/garret`).

### 4. DNS

Two records pointing at the edge (legion-node1):

| Name | Cloudflare mode |
| --- | --- |
| `cache.jeiang.dev` | Proxied (orange) is fine — only narinfo and 302 redirects cross it |
| `cache-push.jeiang.dev` | **Grey-clouded / DNS-only, required** |

A push is one streaming PUT of a whole compressed NAR; Cloudflare rejects
bodies over 100 MB on the free plan, so a proxied push hostname 413s on any
sizeable closure.

### 5. Pocket ID client

Register a new OIDC client named `garret` at `https://auth.jeiang.dev`:

- Enable the device authorization grant (`garret login` uses it).
- Restrict it to the admin group in Pocket ID's own UI — that restriction
  *is* the authorization gate. `allowed_groups` is deliberately empty in
  Nix, so anyone who can obtain a token for this client can push.

Paste the client id into `modules/nixos/garret/default.nix` as
`pocketIdAudience`, replacing the placeholder.

### 6. Signing key

Already generated as `cache.jeiang.dev-1`; its public half
(`cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA=`) is
already in `modules/nixos/nix.nix`, `modules/darwin/nix.nix`, both
workflows, and `zakkart-bootstrap.md`. Only the private half still needs
placing, in sops below.

To generate a replacement (the key name is positional, not a flag):

```bash
nix run github:jeiang/garret#garret-admin -- key generate cache.jeiang.dev-2 ./key
```

```bash
nix run github:jeiang/garret#garret-admin -- key show ./key
```

### 7. sops secrets

```bash
just sops-create modules/nixos/garret/secrets.yaml
```

| Secret | Value |
| --- | --- |
| `garret/s3-access-key-id` | MEGA S4 application key id for the `garret` bucket |
| `garret/s3-secret-access-key` | Its secret |
| `garret/signing-key` | The full nix-format private key from step 6 |

The `.sops.yaml` creation rule already encrypts this shard to the operator
and legion-node4.

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
`.ci/garret.toml` and set `oidc.client_id`/`oidc.audience` to the Pocket ID
client from step 5 (the checked-in one is shaped for the GitHub Actions
path, which needs no login).

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
(`modules/nixos/garret/default.nix`). Attic never evicted anything, so this
is the first cache here that does.

### Key rotation

`signingKeyFiles` is a list precisely so a rotation can overlap: add the new
key alongside the old, deploy, run `garret-admin resign` to backfill
signatures, add the new public key to every consumer's
`trusted-public-keys`, and only then drop the old one from both places.

### Losing the SQLite index

`/mnt/garret/garret.db` is the only record of what the bucket contains —
losing it strands every stored object as an orphan GC cannot reclaim. That
is why the Volume is backed up (`restic-backups-garret.service`). Restore it
per [`restore.md`](restore.md) with both units stopped.

If the index is genuinely unrecoverable, the cheapest fix is to empty the
`garret` bucket and let CI re-push, rather than leave orphans accruing
storage cost.

## Retirement of Attic

Attic is read-only from this change onward — every `w`/`tw` grant in
`modules/nixos/attic/default.nix` is `0`, and CI pushes only to garret. It
keeps serving pulls so pre-cutover paths still resolve.

Retiring it is a separate change: remove `modules/nixos/attic/`, its
inventory entry, its edge route, the `attic` flake input and
`modules/packages/attic.nix`, the `attic.jeiang.dev` substituter and
`default:` key from both nix modules and CI, its blackbox probe and crowdsec
whitelist entry, and its external Postgres. Its `attic` bucket can be
deleted at the same time.
