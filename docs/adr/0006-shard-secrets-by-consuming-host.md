# Shard secrets by consuming host

`modules/nixos/sops/secrets.yaml` held every runtime secret for the whole
fleet, encrypted to every host plus the Human Administrator. That contradicted
a boundary DESIGN.md already declared (State And Backup Boundaries: "Runtime
service secrets use sops-nix files encrypted only to the Human Administrator
and assigned host. Do not give every host access to every application
secret."). The single-file layout is what made the violation unavoidable: one
`sopsFile`, one set of recipients, so any secret landing in it reached every
host whether that host ran the consuming service or not. This ADR is not a new
decision; it is the split that makes the existing boundary hold.

The file replacing it is twelve per-service **Secret Shards**
(`modules/nixos/sops/secrets.<shard>.yaml`, one `.sops.yaml` creation rule
each). A shard is **module-scoped**, not node-scoped: its secrets live with
the NixOS module(s) that consume them, and its recipients are exactly the
Human Administrator plus the host(s) that run those consuming module(s). Node
scoping was tried first and rejected — several secrets are legitimately
consumed by more than one host, and forcing a per-node file would either
duplicate the value across files or silently under-grant one of the
consumers. `secrets.crowdsec.yaml` is the clearest case: the CrowdSec engine
on the edge node registers the bouncer keys, and the NetBird reverse proxy on
legion-node2 authenticates with one of them as a bouncer client — two modules
on two hosts, one shard, encrypted to both. Per-service granularity is the
coarsest boundary that still lets every module reach only the secrets it
actually consumes.

Least privilege is applied past the module/node split where it costs nothing:
`secrets.restic.yaml` is encrypted to the Human Administrator and every node
with a Backup Set, but not the edge node, which runs no backup job and gains
nothing from holding the repository password. `secrets.admin.yaml` is the
other edge case — one non-runtime key stashed for the administrator's own use,
consumed by no module and no host, so its shard is encrypted to
`user_aidanp` alone. The retired `solder` host is dropped from every shard;
it was a recipient on the old monolith only by inertia.

## Consequences

- Adding a secret now means choosing (or creating) its shard and, for a new
  shard, adding a `.sops.yaml` creation rule — there is no longer a default
  file a new `sops.secrets` declaration can silently fall into.
- Multi-host secrets are explicit: a shard's recipient list is the visible
  record of which hosts can decrypt it, rather than an implicit "everyone."
- A compromised node's blast radius is limited to the shards its own modules
  declare, not the fleet's entire secret set.
- `just sops-updatekeys` after any recipient change (new host, decommissioned
  host, host key rotation) now potentially touches multiple shard files
  instead of one; the `fd` glob it and `sops-edit` use already enumerates all
  of them.
