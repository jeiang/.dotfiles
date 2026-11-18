# Decisions: Legion services

Monitoring, the edge, the cache, DNS, and the sites and identity services that run on Legion. These constrain changes; read [`AGENTS.md`](../../AGENTS.md) first.

- Blackbox probes target private backend addresses, never public URLs.
  Probes through the edge would get the prober banned by CrowdSec.
- Anubis gates only the static content sites. Never put it in front of a
  machine client (substituters, OIDC, NetBird gRPC,
  Prometheus). Its challenge store stays in memory. Both Gatus instances
  resolve the content sites to the edge's private or mesh address, and the
  edge serves exactly those two sources without a challenge.
- Stateless by choice: Gatus stores results in memory.
- Every NixOS host uploads its journal to VictoriaLogs on zantark and keeps
  1 GB locally (`modules/journald.nix`). On artemis the upload cursor is in
  `/var/lib/private`, persisted as a whole because systemd refuses a private
  root that is not `0700`. A unit whose routine messages are noise carries
  `LogFilterPatterns`; a filtered message never reaches the journal.
- `gatus-atl` on ricklent is the independent Atlanta watchdog: the same
  endpoints as zantark's `gatus`, alerting straight to Discord with
  `modules/gatus/secrets.yaml`, so it does not depend on zantark.
  zantark's `gatus` keeps alerting through Alertmanager.
- The H@H backup keeps the full cache: a restore costs less than earning
  back H@H trust and quota.
- `cache.jeiang.dev` and `cache-push.jeiang.dev` stay DNS-only in
  Cloudflare. Cloudflare rejects push bodies over 100 MB, and a proxied
  puller gets shared-PoP bans. The signing key `cache.jeiang.dev-1` is named
  for the function, not the implementation.
- garret accepts pushes from a Pocket ID client and from GitHub Actions OIDC
  tokens of the workflows in its `job_workflow_refs` (`ci.yml` of
  `jeiang/.dotfiles`, `jeiang/garret`, `jeiang/atrium` and `jeiang/ripper`,
  ripper's `release.yml`, renpy_proj's `garret.yml`, `nix.yml` of
  `jeiang/erdtree` and `jeiang/cod4-decomp`), pinned by
  repository id, on `push` and `workflow_dispatch`, for `refs/heads/main`,
  `refs/heads/master` (erdtree's default branch) and
  `refs/tags/v*` (release tags, which are unprotected, so `ref_protected`
  stays unset). A new pushing repository or workflow needs its entries in
  `modules/garret/default.nix` first.
- garret's Puller runs as its own user with its own GetObject-only S3 key
  (`garret/puller-s3-*`); only the Pusher holds the bucket-write key. Its backup is an online
  `garret-admin backup` copy, so a backup never stops the cache.
- garret runs on `peria`; its own Caddy terminates `cache` and `cache-push`
  directly instead of alda's edge or Atlanta. Its SQLite index lives on
  the root disk with a six-hourly restic job, so a lost peria forgets pushes
  since the last snapshot. Both units skip their start while the index is
  missing: the Pusher would create an empty one, and its startup orphan
  sweep would then delete every bucket object older than 24 hours. This
  Caddy has no bouncer module or AppSec; peria's host nftables bouncer uses
  alda's LAPI with its key in `modules/crowdsec/secrets.peria.yaml`.
- The portfolio on `vida` runs whatever upstream `joshua-noel/portfolio`
  main builds: `portfolio-update` builds it as the `portfolio` user at
  00:00 UTC (and 2 minutes after activation) into
  `/var/lib/portfolio-update/current`, the GC root, and restarts the
  service when the path changes. Its owner's pushes go live without review,
  so the service exchanges packets only with the edge (`IPAddressAllow`): it
  reaches neither the internet, the private network, nor loopback.
  The `portfolio` flake input supplies only the NixOS module and the
  fallback package used until a first build exists; bump it when the
  module changes.
- The website on alda's edge follows the same pattern as the portfolio:
  `website-update` builds `github:jeiang/website` as the `caddy` user
  nightly (and 2 minutes after activation) into
  `/var/lib/website-update/current`, the GC root Caddy and Anubis read
  per request, so a new build needs no restart. `website-fallback` holds
  the root at the pinned `website` input until a first build exists; that
  input is only the fallback.
- `dns/dnsconfig.js` is the source of truth for the Cloudflare zones. CI
  applies it on merge with full purge; only `_acme-challenge` TXT records
  are ignored. The DNS-only A/AAAA records of Legion services come from each
  `legion.services.<name>.publicHostnames` through `dns/nodes.json`, which
  `just dns-nodes` regenerates (the `legion-nodes-json` check fails while it
  is stale); apex, wildcard, mail, CAA and TXT records stay hand-written. A
  dashboard edit is for emergencies and must be copied back into the file.
  `noelejoshua.com` is in its owner's Cloudflare account.
- Pocket ID's application settings are declared in Nix under
  `UI_CONFIG_DISABLED`, which ignores the database's copy and locks the admin
  UI's settings page: an undeclared setting takes Pocket ID's default. The SMTP
  password reaches it from sops through `services.pocket-id.credentials`.
