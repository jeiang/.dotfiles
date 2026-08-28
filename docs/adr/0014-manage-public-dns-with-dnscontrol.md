# Manage public DNS with dnscontrol

The Cloudflare-hosted zones — jeiang.dev, aidanpinard.co, pinard.co.tt —
move from hand-edited dashboard records to `dns/dnsconfig.js`, applied by
dnscontrol. The repo is the single source of truth: CI previews the
resulting corrections on every PR touching `dns/`, applies them on merge to
main, and a weekly scheduled run fails red when live state has drifted from
the file (`.github/workflows/dns.yml`).

The proximate motivation is that the zone's load-bearing invariants lived
only as comments in `modules/nixos/edge/default.nix`: cache-push.jeiang.dev
must stay grey-clouded (Cloudflare 413s NAR pushes over 100 MB),
cache.jeiang.dev stays grey to keep CI pulls clear of shared-PoP bans
(docs/adr/0013), and the NetBird control-plane hostnames stay grey for
their gRPC/WebSocket streams. A dashboard misclick on any of these breaks
CI or the VPN weeks later with nothing in review history. In
`dnsconfig.js` the proxy status is a per-record `CF_PROXY_*` token that a
PR diff shows and a push enforces.

## Decisions

- **dnscontrol, not octodns or Terraform.** One Go binary from the
  flake-pinned nixpkgs, orange/grey cloud as a first-class record modifier,
  and `preview`/`push` map directly onto plan-on-PR/apply-on-merge.
  Terraform's state file is machinery with no payoff at three zones;
  octodns's YAML-as-data would only earn its Python provider stack if zone
  files were ever generated from Nix, which nothing needs today.
- **Full purge.** A record absent from `dnsconfig.js` is deleted from the
  live zone. The only exceptions are the `_acme-challenge` TXT records,
  IGNOREd because Caddy's DNS-01 issuer creates and deletes them via the
  API at every renewal, and a push racing a renewal must not delete a
  challenge mid-validation.
- **CI applies.** Merged means live; there is no manual apply step to
  forget. The workflow runs only for non-fork PRs, and the
  `CLOUDFLARE_DNS_TOKEN` repository secret is a dedicated token scoped to
  Zone:Read + DNS:Edit on exactly these three zones — separate from
  Caddy's DNS-01 token so either can be revoked without breaking the
  other. Worst case for a compromised token or malicious merge is bounded
  to DNS on these zones and revocable in one click.
- **Emergency dashboard edits are allowed, but not done.** During an
  incident the dashboard is the faster path and stays available; the fix
  is only finished once back-ported into `dnsconfig.js`, and the weekly
  drift check nags until it is. Without the back-port, the next unrelated
  DNS merge silently reverts the emergency fix — that silent revert is the
  failure mode the drift check exists to catch.
- **noelejoshua.com stays out.** It is hosted on its owner's behalf in a
  separate Cloudflare account, and its certificate already renews over
  HTTP-01 with no DNS coupling (modules/nixos/edge/default.nix). A repo
  gating changes to someone else's domain is coupling with no payoff.

## Consequences

- The dashboard becomes read-only by policy for these zones. Routine
  record changes are PRs; `just dns-preview` gives the same diff locally
  using Caddy's sops-held token (preview only reads).
- The initial import was verified exact: `dnscontrol preview` against the
  hand-reviewed export reported zero corrections before the first push,
  so purge semantics were enabled against a known-identical baseline.
- Records for new services usually need no DNS change at all: the apex +
  wildcard records already route every subdomain to the edge, so only
  hostnames whose proxy status or target differs (grey-cloud, non-node1)
  get explicit records.
