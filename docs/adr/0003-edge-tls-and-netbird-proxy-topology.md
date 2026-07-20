# Edge TLS and NetBird proxy topology

The Edge Node terminates public TLS for every host it can reach with a
directly issued certificate, and stays out of the way for the one host that
needs to own its own. `jeiang.dev`/`*.jeiang.dev` share one ACME DNS-01
wildcard certificate against Hetzner DNS; `aidanpinard.co` and
`pinard.co.tt` are separate per-zone DNS-01 certificates against the same
provider. `noelejoshua.com` and the `plyrex.dev` hosts are not in Hetzner
DNS, so they fall back to Caddy's standard HTTP-01/on-demand issuance, which
only succeeds once each host's DNS already points at the Edge Node.

`proxy.jeiang.dev`/`*.proxy.jeiang.dev` is a second-level wildcard outside
the `*.jeiang.dev` SAN, and belongs to the NetBird reverse proxy rather than
the edge. It is provisioned host-side on `legion-node2` via NixOS's
`security.acme` (lego) DNS-01 against Hetzner DNS and handed to the reverse
proxy as a static certificate directory; the proxy's own file watcher picks
up renewals without a restart, so it never runs its own ACME client.

Edge topology stays a single Caddy instance on `legion-node1`. For every host
except the NetBird proxy hosts, Caddy terminates TLS locally and reverse
proxies to the backend over the Hetzner private network. For
`proxy.jeiang.dev`/`*.proxy.jeiang.dev`, a `caddy-l4` listener wrapper
matches the SNI ahead of the `tls` wrapper and forwards the raw TCP stream to
`legion-node2:443` wrapped in PROXY protocol v2. This lets the reverse proxy
own the whole TLS handshake and open arbitrary custom published ports
without competing with the edge for port 443 or certificate ownership.

Legion nodes join the NetBird mesh as ordinary peers, replacing the
Kubernetes routing peer this migration drops. Peer-only services — Blocky
DNS, raw VictoriaMetrics/VictoriaLogs — are reachable exclusively over the
NetBird tunnel via `trustedInterfaces`, with no public or private Hetzner
firewall opening.

CrowdSec runs as a single LAPI+AppSec instance beside the edge Caddy,
configured fail-open: a CrowdSec restart or outage must not take down the
single-node edge. The cluster ran fail-closed, but that posture depended on
HA AppSec replicas that no longer exist. Because the L4 passthrough never
reaches Caddy's own CrowdSec handlers, the NetBird reverse proxy runs its
own bouncer against the same LAPI over the private network, so passthrough
traffic still has coverage.

Attic runs against an external managed PostgreSQL with no local state — a
decision settled before this migration, recorded here because it shaped
this migration's placement and backup decisions (no Volume, no Backup Set
for Attic).

The Caddy admin API stays bound to its module default (localhost-only);
metrics are exposed instead through a dedicated private-network-only site on
port 2020, so cross-node scraping never needs an unauthenticated
config-mutation surface.

## Consequences

- The Hetzner DNS API token is live on two nodes (edge Caddy and the NetBird
  reverse proxy) instead of one central issuer.
- Fail-open CrowdSec trades strict enforcement for single-node availability:
  an LAPI outage means an enforcement gap, not an edge outage.
- Edge CrowdSec never inspects `proxy.jeiang.dev` traffic; coverage for that
  path depends entirely on the reverse proxy's own bouncer.
- `noelejoshua.com` and the `plyrex.dev` hosts have a cert-issuance gap at
  cutover: HTTP-01/on-demand TLS cannot succeed until each host's DNS
  already points at the Edge Node, so the first requests after cutover may
  hit an untrusted or absent certificate.
- Losing `legion-node2`'s local ACME state costs a DNS-01 reissuance, not a
  recovery problem, since the proxy's certificate is wildcard and rate-limit
  headroom is generous.
- A peer-only service behind the NetBird tunnel has no fallback reachability
  path; moving it off `legion-node2` requires rejoining the mesh.
