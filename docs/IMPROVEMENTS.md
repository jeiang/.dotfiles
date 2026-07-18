# Improvements

Open work, listed in recommended implementation order. Completed changes
belong in Git history; enduring constraints and decisions belong in
[`DESIGN.md`](DESIGN.md), [`CONTEXT.md`](../CONTEXT.md), or an ADR.

## 1. Establish Automated Backups

Use NixOS `services.restic.backups` with a dedicated Mega S4 bucket and
sops-nix-managed credentials.

- Run encrypted backups daily, retain 30 days, and perform a documented restore
  test quarterly.
- Give each stateful service an explicit Backup Set and quiesce hooks where a
  consistent SQLite or application snapshot requires them.
- Back up authoritative service data from directly mounted Hetzner Volumes.
  Exclude disposable caches and the one-month monitoring data unless a later
  recovery requirement says otherwise.
- Give Artemis an explicit backup allowlist for irreplaceable user and
  application data. Exclude downloads, games, Steam data, caches, and generated
  outputs by default.
- When repository-managed persistence is enabled for a host, reject any backup
  path that is not also present in its persistence configuration.
- Store restore instructions beside the service or host configuration they
  recover.

## 2. Make Legion Fleet Rollouts Fail Fast

Replace the alphabetical `deploy-legion` loop with inventory-derived rollout
metadata.

- Deploy ordinary service nodes before the bootstrap or Edge Node.
- Deploy `legion-node1` last while it is the K3s bootstrap node and after it
  becomes the Caddy Edge Node.
- Stop immediately when any evaluation, copy, activation, or verification step
  fails.
- Keep single-node deployment available for staged recovery and migration work.

## 3. Remove Unused Flake Inputs

Remove inputs that have no callers:

- `nix-minecraft`
- `website`
- `nix2container`
- `mk-shell-bin`
- `nixos-facter-modules`, because the pinned nixpkgs already provides the
  `hardware.facter` module used by the hosts

Update `flake.lock`, then evaluate every host and run the package and flake
checks to catch any hidden dependency before merging.

## 4. Separate Anonymous Cache Reads From Trusted Writes

The Attic cache is publicly readable, but CI still performs OIDC login on pull
requests.

- Configure the public cache as an anonymous substituter for discovery and
  build jobs.
- Request an OIDC token and log in to Attic only for trusted `main` runs that
  may push.
- Treat a failed cache push on a trusted run as a failure instead of suppressing
  every push error.
- Preserve separate checks for every `x86_64-linux` package, every NixOS system
  closure, treefmt, Statix, and deploy-rs.

## 5. Migrate Legion To Host-Native Services

Replace the transitional Experimental Cluster with explicitly placed
Host-Native Services on `legion-node1` through `legion-node4`. Follow
[ADR 0002](adr/0002-migrate-legion-to-host-native-services.md).

Three workloads run only on the Experimental Cluster and are absent from the
Kubernetes manifests repository: the `jkmn-website` static site
(`noelejoshua.com`), Stirling PDF (`pdf.plyrex.dev`), and the Tailscale reverse
proxy publishing `jellyfin.plyrex.dev` and `seerr.plyrex.dev`. Include them in
the migration inventory; do not derive the inventory from the manifests
repository alone.

### Capacity And Placement

- Measure steady-state CPU, memory, storage, and dependencies for every current
  workload before assigning it to a node. The existing nodes have roughly
  2 GB of RAM each, so do not infer placement from Kubernetes requests alone.
- Fix `legion-node1` as the Edge Node. Leave all other assignments unresolved
  until the capacity audit is complete.
- Encode every final assignment in the central Legion inventory. Moving a
  stateful service is a planned data migration, not automatic failover.
- Add evaluation checks for exactly one Edge Node, placements that reference
  existing nodes, unique public hostnames, and required Volume and backup
  declarations for stateful services.

### Service Modules

- Use first-party NixOS modules for Actual Budget, Attic, Blocky, Pocket ID,
  and Stirling PDF. Stirling PDF keeps login enabled and moves its authoritative
  data from the cluster-provisioned 10 GiB Hetzner Volume to a directly mounted
  Volume on its assigned node.
- Compose the first-party component modules behind local modules for monitoring
  and CrowdSec.
- Build a local NetBird module for the deployed server, relay, reverse proxy,
  identity, and state topology rather than forcing it through the mismatched
  first-party server abstraction.
- Use thin local modules for H@H and project-specific static sites.
- Render the `jkmn-website` content to static HTML and serve `noelejoshua.com`
  directly from the Edge Node Caddy as an ordinary static site, retiring its
  nginx container and ConfigMap-embedded pages.
- Keep application source in its application repository. This flake owns the
  NixOS service definition, placement, state, secrets, and lifecycle.

### Edge And Network

- Run a single Caddy instance on `legion-node1`; point public DNS directly to
  that node and remove the Hetzner load balancer after all routes have moved.
- Build Caddy reproducibly with the CrowdSec HTTP and AppSec handlers. Preserve
  IP remediation, AppSec, the Attic traffic exception, and exclusions for
  long-lived NetBird streams.
- Re-enable the NixOS firewall on every Legion node. Expose public HTTP and HTTPS
  only on the Edge Node, and permit backend traffic only over the Hetzner
  private network.
- Terminate public TLS at Caddy. Backend HTTP over the firewalled Hetzner private
  network is the accepted transport boundary.
- Replace the cluster's Tailscale-plus-Caddy proxy pod by joining the Edge Node
  to the tailnet with `services.tailscale` and adding Caddy routes for
  `jellyfin.plyrex.dev` and `seerr.plyrex.dev` that proxy to the existing
  tailnet peer. Deliver the Tailscale auth key through sops-nix scoped to the
  Edge Node. These two routes are the only accepted exception to the
  private-network backend transport boundary; their backend hop rides the
  tailnet.
- Keep DNS, Hetzner Cloud Firewall, server, and Volume provisioning outside this
  repository. Document their required records, rules, IDs, and attachments.

### State, Secrets, And Migration

- Keep authoritative service state on directly mounted Hetzner Volumes and use
  node-local storage only for Disposable State.
- Replace the Bitwarden Kubernetes operator with sops-nix. Encrypt each service
  secret file only to the Human Administrator and its assigned node; keep shared
  infrastructure secrets separate and narrowly scoped.
- Run Caddy and Host-Native Services alongside K3s during migration. Move and
  verify one service at a time, including backup and restore behavior, before
  removing its Kubernetes deployment.
- After the final service is stable, remove K3s and its platform components,
  verify that `legion-node5` owns no workload or Volume, remove it from the
  inventory, and decommission it as the final migration step.
