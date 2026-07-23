# Probe service health from inside the private network

Synthetic uptime probing (`blackbox_exporter`, run on the monitoring node)
targets each first-party service's **private backend** address over the Legion
private network — pocket-id, Actual Budget, Attic, and the NetBird management
server on their internal ports — rather than their public `https://` hostnames.
The obvious alternative is to probe the public URLs, which would additionally
exercise DNS, the Edge Node's Caddy, TLS termination, and CrowdSec — the full
path a real user takes. That coverage is deliberately declined here.

The deciding factor is CrowdSec. Every public request to a first-party
hostname passes through the Edge Node's CrowdSec-instrumented Caddy. A blackbox
prober hitting those URLs on a fixed interval, forever, is exactly the traffic
shape an IP-reputation engine is built to punish: repetitive, unattended,
non-human. Probing public URLs would therefore require carving a permanent
prober-IP exemption into CrowdSec — coupling the monitoring node's health
checks to the security posture of the edge, and creating a standing whitelisted
source that weakens that posture. Probing the private backends sidesteps this
entirely: the traffic never reaches the edge or CrowdSec, needs no exemption,
and cannot self-ban the fleet.

Private-backend probing also needs no new network surface. Each targeted
backend port is already reachable on the trusted private interface (`enp7s0`)
because its owning service declares that port in the Legion service inventory;
the monitoring node reaches them the same way it already scrapes every
cross-node metrics endpoint. No host firewall opening and no Hetzner Cloud
Firewall rule is added for probing.

The cost is that probes confirm "the service answers on its backend port," not
"a user on the internet can reach it." End-to-end reachability of the public
chain is left to be observed indirectly — the Edge Node's own Caddy metrics
already expose per-upstream health and latency for every proxied hostname — and
a dedicated public-path probe can be added later behind an explicit CrowdSec
exemption if a real end-to-end blind spot appears.

## Consequences

- Blackbox probes detect backend-level outages (service down, not listening,
  not answering) but not edge, DNS, TLS, or CrowdSec failures on the public
  path; those remain covered by Caddy upstream metrics and by the CrowdSec
  dashboard.
- No CrowdSec exemption exists for the prober, and none is created; the edge's
  IP-reputation posture is unchanged by the addition of monitoring.
- Probing adds no host or cloud firewall openings — targets are existing
  private-scope backend ports on the trusted interface.
- Adding true public-path probing later is a deliberate, separately-justified
  step (a whitelisted prober identity in CrowdSec), not an incremental tweak.
