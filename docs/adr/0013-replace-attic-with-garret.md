# Replace Attic with garret

The Nix binary cache moves from Attic (the `jeiang/attic` OIDC-enabled fork,
`modules/nixos/attic/`) to garret (`jeiang/garret`,
`modules/nixos/garret/`), a purpose-built single-tenant cache for this
infrastructure.

garret splits the cache into two units instead of one server: a **Pusher**
carrying an OIDC-authenticated push API, and a **Puller** serving a
standard, anonymous Nix substituter. They are colocated on legion-node4 over
a shared SQLite index and a MEGA S4 bucket. Structurally this buys three
things Attic could not give us here: the Puller answers NAR requests with a
302 to a presigned S3 URL rather than streaming the body, so NAR bytes stop
crossing the edge entirely; both binaries expose Prometheus metrics, where
Attic exposed none; and eviction becomes quota + LRU rather than Attic's
time-based retention, which we ran with a zero retention period, i.e. never
evicting anything.

## Cutover

There is no migration path — the S3 layout and index schema share nothing
with Attic's — so this is a side-by-side cutover rather than a swap:

- garret stands up on new hostnames, a new bucket, and a new signing key.
- Attic keeps running and keeps serving pulls, so nothing already cached is
  lost, but it stops receiving pushes: every `w`/`tw` grant in
  `modules/nixos/attic/default.nix` is set to `0`, and CI pushes only to
  garret.
- Both substituters and both public keys are listed fleet-wide during the
  window.
- Attic is deleted in a separate retirement change once nothing useful is
  left in it.

Making Attic read-only rather than dual-pushing is what makes this fit:
legion-node4 has 1.9 GiB of RAM and 2 vCPUs, and dual-pushing would peak
both servers' upload buffers simultaneously. A read-only atticd never
allocates them, so its `MemoryMax` drops from 896M to 256M and garret's two
units take the freed budget.

## Naming

The hostnames are `cache.jeiang.dev` (Puller) and `cache-push.jeiang.dev`
(Pusher), and the signing key is `cache.jeiang.dev-1` — deliberately named
after the function rather than the implementation, because these strings are
baked into every machine's `nix.conf` and into CI. Replacing the
implementation again should not mean another fleet-wide rename.

Both hostnames are grey-clouded / DNS-only in Cloudflare.

For `cache-push.jeiang.dev` this is a hard requirement: a push is one
streaming PUT of an entire zstd-compressed NAR, and Cloudflare rejects
bodies over 100 MB on the free plan.

For `cache.jeiang.dev` it is a choice. Proxying it would gain almost
nothing — garret answers NAR requests with a 302 to a presigned S3 URL, so
only narinfo would ever be cacheable — while inheriting the shared-PoP
failure mode that kept the cache unreachable from CI: a CrowdSec decision
landing on a Cloudflare address 403s every client routed through that PoP.
That underlying bug is fixed separately, but a cache has no reason to sit
behind a proxy it does not benefit from.

## Consequences

- **legion-node4 becomes stateful for the cache.** Attic used an external
  managed Postgres and held nothing locally. garret's SQLite index is the
  only record of what the bucket contains, so losing it strands every stored
  object as an orphan GC can never reclaim. It gets a Hetzner Volume at
  `/mnt/garret` and a restic backup set, with both units in
  `backupPauseUnits` for a consistent snapshot.
- **The CI push authorization is not identical.** Attic granted push on
  `ref_protected = "true"` — any protected branch of any repo owned by this
  account. garret implements no such check, only trailing-`*` globs against
  the `ref` claim, so the rule is now `refs/heads/main`. An unprotected
  `main` in another owned repo would be accepted where Attic refused it.
- **Human push moves from role claims to a Pocket ID client.** Attic keyed
  on a custom `attic_role` claim with admin/writer/reader tiers. garret has
  no tiers — an accepted token means full push — so the gate is the Pocket
  ID client's own group restriction, editable without a deploy.
- **CI loses its login step.** The garret client mints its own token from
  the GitHub Actions OIDC provider, so `.ci/attic-login-push.sh` has no
  successor; `.ci/garret-push.sh` keeps the watchdog, retry, and soft-fail
  behaviour of the script it replaces.
- **CI push jobs build the client from source until garret seeds it.**
  `attic-client` installs quickly because `jeiang/attic`'s own CI pushes each
  rev's build into the cache. `jeiang/garret` has no equivalent job yet, so
  every push job compiles a Rust workspace until one is added there.
- **The store watcher is available but unused.** garret ships a third module
  that auto-pushes locally built paths from build machines. It needs a Pocket
  ID confidential client per machine and a root-running unit, and is left for
  a later change.
