# Runbook: Edge Cutover

Operator runbook for [`docs/MIGRATION.md`](../MIGRATION.md) piece 1.5: moving
public traffic from the Hetzner Load Balancer/Traefik (Experimental Cluster)
to the Edge Node (`legion-node1`, `modules/nixos/edge/`). Review
[`AGENTS.md`](../../AGENTS.md) before running any command here.

This runbook only cuts DNS for the Edge Node's own routes. It does not
delete the Hetzner Load Balancer, remove Traefik, or touch K3s — those are
Cutover Safety Rule 3 (`docs/MIGRATION.md`), Phase 7 only.

## Prerequisites

### sops secrets

Create these with `just sops-edit` before the CrowdSec enablement step
below (the site/redirect/placeholder routes need only
`caddy/hetzner-dns-token`, already required since piece 1.1):

| Secret | Value |
| --- | --- |
| `caddy/hetzner-dns-token` | Hetzner DNS API token (DNS-01 issuance) |
| `caddy/crowdsec-lapi-url` | `http://127.0.0.1:8080` (the edge Caddy bouncer talks to the LAPI on loopback, same host) |
| `caddy/crowdsec-lapi-key` | A random key you choose (e.g. `openssl rand -hex 32`). This is both what Caddy sends as its bouncer key and what `modules/nixos/crowdsec/default.nix`'s `crowdsec-bouncers` service registers as the `edge-caddy` bouncer's key — same value, one secret. |
| `crowdsec/bouncer-netbird-proxy-key` | A random key you choose, same way. Registered at the LAPI now; consumed by legion-node2's netbird-proxy bouncer client when piece 3.2 lands (grant node2 access with `just sops-updatekeys` at that point). |

### Hetzner Cloud Firewall

Add inbound rules for `legion-node1`'s public IPs
(`178.156.226.145` / `2a01:4ff:f0:6b8e::1`, `modules/hosts/legion/default.nix`
`legionNodes.legion-node1`) allowing TCP 80 and 443 from anywhere. Leave the
existing rule set for the Hetzner Load Balancer untouched — it keeps serving
traffic for every host not yet cut over, and removing it is Phase 7.

### Capacity audit

Confirm `docs/MIGRATION.md` piece 0.6 has recorded measured CPU/memory for
the Edge Node's workloads (Caddy, CrowdSec) against `legion-node1`'s ~2 GB
RAM and that the placement table's `MemoryMax` values reflect it. Piece 0.6
blocks the first service cutover, not code landing — do not proceed past
"Staged DNS cutover" below until it's recorded.

### Deploy

```sh
just deploy legion-node1
```

Confirm `edge.crowdsec.enable` in `modules/hosts/legion/default.nix` (via
`modules/nixos/edge/default.nix`) matches intent for this deploy — it
should stay `false` until the "CrowdSec enablement" step below, so the
edge can go live and be verified with `curl --resolve` before CrowdSec is
part of the picture at all.

## Pre-cutover verification

Run every check against `legion-node1`'s public IP with `--resolve`, before
any DNS record moves. Replace `178.156.226.145` if the node's address has
changed since this was written (`modules/hosts/legion/default.nix`).

Static sites (expect `200`):

```sh
curl -sSI --resolve jeiang.dev:443:178.156.226.145 https://jeiang.dev/
curl -sSI --resolve aidanpinard.co:443:178.156.226.145 https://aidanpinard.co/
curl -sSI --resolve pinard.co.tt:443:178.156.226.145 https://pinard.co.tt/
curl -sSI --resolve noelejoshua.com:443:178.156.226.145 https://noelejoshua.com/
curl -sSI --resolve bill-split.jeiang.dev:443:178.156.226.145 https://bill-split.jeiang.dev/
curl -sSI --resolve netbird.jeiang.dev:443:178.156.226.145 https://netbird.jeiang.dev/
```

Stray subdomain under the wildcard (expect `404`):

```sh
curl -sSI --resolve nope.jeiang.dev:443:178.156.226.145 https://nope.jeiang.dev/
```

Redirect (expect `301` to `https://github.com/jeiang`):

```sh
curl -sSI --resolve github.jeiang.dev:443:178.156.226.145 https://github.jeiang.dev/
```

Placeholders (expect `503`, and note these two hosts are **not** in Hetzner
DNS — see the HTTP-01 gap below):

```sh
curl -sSI --resolve jellyfin.plyrex.dev:443:178.156.226.145 https://jellyfin.plyrex.dev/
curl -sSI --resolve seerr.plyrex.dev:443:178.156.226.145 https://seerr.plyrex.dev/
```

Proxied backends (expect `502`/connection refused until their piece lands —
that is the expected pre-cutover state, not a failure of the edge route
itself; re-run after the corresponding piece deploys):

```sh
curl -sSI --resolve auth.jeiang.dev:443:178.156.226.145 https://auth.jeiang.dev/    # Pocket ID, piece 4.1
curl -sSI --resolve attic.jeiang.dev:443:178.156.226.145 https://attic.jeiang.dev/  # Attic, piece 5.1
curl -sSI --resolve budget.jeiang.dev:443:178.156.226.145 https://budget.jeiang.dev/  # Actual Budget, piece 5.2
curl -sSI --resolve grafana.jeiang.dev:443:178.156.226.145 https://grafana.jeiang.dev/  # Monitoring, piece 6.1
```

NetBird gRPC/WebSocket paths (TLS/SNI + backend reachability check; expect a
TLS handshake to succeed now, `502`/connection refused on the actual paths
until piece 3.1's backend lands):

```sh
curl -sSI --resolve netbird.jeiang.dev:443:178.156.226.145 \
  https://netbird.jeiang.dev/management.ManagementService/
curl -sSI --resolve netbird.jeiang.dev:443:178.156.226.145 \
  https://netbird.jeiang.dev/signalexchange.SignalExchange/
curl -sSI --resolve netbird.jeiang.dev:443:178.156.226.145 \
  https://netbird.jeiang.dev/ws-proxy/
```

Layer-4 SNI passthrough for the NetBird reverse proxy (TLS/SNI-only check —
this never terminates at the edge, so `curl` can't get an HTTP response out
of it; a successful TLS handshake through to *something* on node2:443 is
the signal, an immediate reset means the SNI matcher isn't routing):

```sh
openssl s_client -connect 178.156.226.145:443 -servername proxy.jeiang.dev </dev/null
openssl s_client -connect 178.156.226.145:443 -servername foo.proxy.jeiang.dev </dev/null
```

Before piece 3.2 (`netbird-proxy` on node2) lands, expect the TCP proxy to
connect and then hang/reset (nothing is listening on node2:443 yet) rather
than a clean handshake — that's still confirmation the edge is routing by
SNI to the right backend, not terminating TLS itself.

## Staged DNS cutover

All hostnames below except `noelejoshua.com` and the `plyrex.dev` hosts are
in Hetzner DNS (self-serve). Move one host (or tightly related group) at a
time, verifying before the next:

- **Lower TTLs first.** At least a day before cutover, drop the TTL on
  every record you're about to move to 60s in the Hetzner DNS Console, so
  a rollback (below) actually takes effect quickly.
- **Move order** (independent static/redirect hosts first, so a mistake
  there doesn't also take out something with a live backend):
  - `jeiang.dev` (A/AAAA apex), `aidanpinard.co`, `pinard.co.tt`,
    `bill-split.jeiang.dev`, `github.jeiang.dev`.
  - `netbird.jeiang.dev` (dashboard is live now; the gRPC/backend routes
    stay `502` until piece 3.1, same as pre-cutover — that's expected,
    not a regression from this step).
  - `auth.jeiang.dev`, `attic.jeiang.dev`, `budget.jeiang.dev`,
    `grafana.jeiang.dev` — only once each service's own migration piece
    (4.1/5.1/5.2/6.1) has actually deployed and been verified per its own
    runbook. Moving DNS ahead of the backend just turns a controlled
    `502` (edge, pre-verified) into a `502` from a different place; do it
    in piece order, not ahead of it.
  - `proxy.jeiang.dev` / `*.proxy.jeiang.dev` — only once piece 3.2's
    `netbird-proxy` is live on node2 (same reasoning as above: don't move
    DNS ahead of the backend it points through to).
- **Per-host verification after each move:** repeat the matching
  `curl --resolve` check from "Pre-cutover verification" above, but
  without `--resolve` (let real DNS resolve now) from a network outside
  the Hetzner private network, and check the Edge Node's Caddy access log
  (`/var/log/caddy/access.log`) for the new traffic.
- **Rollback per step:** point the moved A/AAAA record(s) back at the
  Hetzner Load Balancer's IP. The low TTL from step 1 means this
  propagates in roughly the TTL window; the LB/Traefik path is untouched
  throughout this runbook (Cutover Safety Rule 3), so rollback is a pure
  DNS revert with no service-side action needed.

### Third-party DNS: `noelejoshua.com` and the `plyrex.dev` hosts

`noelejoshua.com`, `pdf.plyrex.dev`, `jellyfin.plyrex.dev`, and
`seerr.plyrex.dev` are not in Hetzner DNS (`docs/MIGRATION.md` TLS
strategy). Coordinate the DNS record change directly with each zone's
owner — this flake has no automation for those zones.

**HTTP-01 cert-issuance gap:** the Edge Node's Caddy only requests a
certificate for these hosts on demand (HTTP-01/TLS-ALPN-01), and that
challenge can only succeed once the host's public DNS actually points at
`legion-node1`. Between the DNS record changing and the first successful
challenge, clients hitting the host over HTTPS will see a certificate
warning (Caddy serves a self-signed/placeholder cert until the challenge
completes, typically seconds to low minutes, but can stall longer if the
authoritative DNS change hasn't fully propagated to the ACME validator's
resolvers). There is no way to pre-issue the cert before the DNS move for
these hosts specifically because HTTP-01 validation requires the DNS to
already point here. Warn the zone owner about the brief warning window
before flipping their record.

`pdf.plyrex.dev` is explicitly **not** part of this runbook — it cuts over
in Phase 5 (piece 5.6/5.3, Stirling PDF), not now.

## CrowdSec enablement

Once the sops secrets above exist and the rest of the edge is verified:

- Set `edge.crowdsec.enable = true` for `legion-node1` and deploy:
  ```sh
  just deploy legion-node1
  ```
- Verify the LAPI and both bouncers registered
  (`modules/nixos/crowdsec/default.nix`'s `crowdsec-bouncers` service runs
  this automatically on boot, but confirm it landed):
  ```sh
  ssh node1.jeiang.dev -- sudo cscli bouncers list
  ```
  Expect `edge-caddy` and `netbird-proxy` both present and not revoked.
- Verify AppSec is responding on loopback:
  ```sh
  ssh node1.jeiang.dev -- sudo cscli lapi status
  ssh node1.jeiang.dev -- curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7422/
  ```
- Confirm fail-open: stop the engine and verify the edge keeps serving
  traffic (`docs/MIGRATION.md` Confirmed Decisions; this must never 503
  the edge):
  ```sh
  ssh node1.jeiang.dev -- sudo systemctl stop crowdsec
  curl -sSI --resolve jeiang.dev:443:178.156.226.145 https://jeiang.dev/
  ssh node1.jeiang.dev -- sudo systemctl start crowdsec
  ```

## Explicit non-steps

- **Hetzner Load Balancer deletion and Traefik removal** are Phase 7 only
  (Cutover Safety Rule 3, `docs/MIGRATION.md`). Nothing in this runbook
  touches either.
- **`jellyfin.plyrex.dev` / `seerr.plyrex.dev`** stay on the static
  placeholder response (piece 1.4). The Tailscale-backed proxy is not
  migrated here; it is deferred to a later date per the accepted ADR 0002
  exception.
- **`pdf.plyrex.dev`** cuts over in Phase 5 (Stirling PDF, piece 5.3/5.6),
  not as part of this runbook.
