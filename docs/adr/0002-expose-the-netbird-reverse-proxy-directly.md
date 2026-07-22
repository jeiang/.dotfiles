# Expose the NetBird reverse proxy directly

The NetBird reverse proxy runs as a public service on its own Legion node
rather than behind the Caddy Edge Node. Public DNS for `proxy.jeiang.dev` and
`*.proxy.jeiang.dev` points straight at the proxy node, and the proxy
terminates its own TLS with a static DNS-01 wildcard certificate. The earlier
design placed a `caddy-l4` SNI passthrough on the edge that forwarded raw bytes
to the proxy; since the proxy already terminates TLS, that hop added coupling
without benefit and constrained custom ports. Going direct lets the proxy
publish arbitrary TCP/UDP services by opening a port in two firewalls and
nothing else. The `caddy-l4` plugin is dropped from the custom Caddy build and
can be re-added if a future passthrough need appears.

Remediation moves to the proxy node because the edge bouncer no longer sees
proxy traffic. CrowdSec IP-reputation runs at the application layer, per
published service and fail-open, and an OS-level CrowdSec firewall bouncer
drops banned source IPs across the whole node. Both take decisions from the
single CrowdSec LAPI on the Edge Node over the private network; the engine
whitelists the Hetzner private network and the NetBird mesh ranges so
tunnel-origin and inter-node traffic is never banned. There is no WAF request
inspection on the proxied path, which is unchanged: the passthrough was raw
bytes and never inspected either.

The proxy node's host firewall opens a bounded reserved port range once for
ad-hoc Layer-4 services, plus exact ports declared in shared flake data for
durable, module-owned services. A separate Hetzner Cloud Firewall dedicated to
the proxy node is the manual per-service gate in both cases; the reserved range
is never opened wholesale on the Hetzner side. A full cross-host abstraction
that would let one module declare both a service and its public exposure is
deferred until a durable published service needs it.

## Consequences

- The proxy node is public-facing rather than a private backend, and owns its
  own IP remediation.
- Custom ports and arbitrary protocols are published by opening the host and
  Hetzner firewalls; no reverse-proxy reconfiguration is required.
- Durable declared ports require a redeploy; ad-hoc ports inside the reserved
  range do not.
- Proxied traffic is protected by IP reputation and OS-level bans, not by
  request-body WAF inspection.
