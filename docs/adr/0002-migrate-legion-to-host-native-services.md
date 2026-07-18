# Migrate Legion to host-native services

The Legion nodes currently form a resource-constrained K3s environment used for
experimentation while also hosting personal services. Migrate those workloads,
one at a time, to explicitly placed Host-Native Services managed by NixOS; then
remove K3s and decommission `legion-node5`. This trades scheduling and automatic
failover for lower RAM overhead, direct ownership of service state, and a simpler
four-node fleet.

`legion-node1` becomes the single Caddy Edge Node and public DNS points directly
to it after the Hetzner load balancer is removed. Caddy terminates public TLS and
proxies over the firewalled Hetzner private network. Preserve CrowdSec IP
remediation and AppSec through a reproducible Caddy plugin build.

Use first-party NixOS service modules where they match the workload, composed
local modules for monitoring and CrowdSec, a custom local NetBird module for its
server, relay, proxy, identity, and state topology, and thin local modules for
project-specific services. Keep authoritative state on attached Hetzner Volumes,
deliver service secrets through recipient-scoped sops files, and back up required
state to Mega S4 with Restic. Provider resource provisioning remains outside this
flake.

## Consequences

- Service placement is explicit in the Legion inventory; no general-purpose
  scheduler or automatic service failover remains.
- The target Legion Fleet is `legion-node1` through `legion-node4`.
- Migration must coexist with K3s until every service, route, Volume, secret, and
  backup has been verified.
- Moving a stateful service between nodes is an operator-controlled Volume and
  data migration.
