# Improvements

Open work, listed in recommended implementation order. Completed changes
belong in Git history; enduring constraints and decisions belong in
[`DESIGN.md`](DESIGN.md), [`CONTEXT.md`](../CONTEXT.md), or an ADR.

## 1. Establish Automated Backups

Use NixOS `services.restic.backups` with a dedicated Mega S4 bucket and
sops-nix-managed credentials.

The Legion side is implemented: `modules/nixos/backups.nix` derives daily,
30-day-retention Restic jobs from each service's inventory-declared Backup
Set and pause units (`modules/hosts/legion/_service-inventory.nix`), backing
up only authoritative data from directly mounted Hetzner Volumes (disposable
caches and monitoring data excluded), rejecting any Backup Set path outside
the service's declared persistence, and documented in
[`docs/runbooks/restore.md`](runbooks/restore.md). Remaining work:

- Give Artemis an explicit backup allowlist for irreplaceable user and
  application data. Exclude downloads, games, Steam data, caches, and generated
  outputs by default.
- Perform a documented restore test quarterly, once Legion services are
  cut over and Artemis backups exist. Each service's cutover runbook already
  exercises a one-time restore per Cutover Safety Rule 1
  ([`docs/MIGRATION.md`](MIGRATION.md)); a recurring quarterly drill is not
  yet scheduled.

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
- `nix2container`
- `mk-shell-bin`
- `nixos-facter-modules`, because the pinned nixpkgs already provides the
  `hardware.facter` module used by the hosts

Update `flake.lock`, then evaluate every host and run the package and flake
checks to catch any hidden dependency before merging.

## 4. Migrate Legion To Host-Native Services

Replace the transitional Experimental Cluster with explicitly placed
Host-Native Services on `legion-node1` through `legion-node4`, per
[ADR 0002](adr/0002-migrate-legion-to-host-native-services.md) and
[ADR 0003](adr/0003-edge-tls-and-netbird-proxy-topology.md).

Code for Phases 0–6 (foundations, Edge Node, backup foundation, NetBird
stack, identity, applications, monitoring) is landed. This flake still
describes the Experimental Cluster as the live deployment
([`DESIGN.md`](DESIGN.md)): remaining work is entirely operator-driven
cutover — running each phase's runbook against the live services, verifying
backup and restore per the Cutover Safety Rules, then Phase 7 teardown (K3s
removal, `legion-node5` decommission). See [`docs/MIGRATION.md`](MIGRATION.md)
for the authoritative phase-by-phase piece list, status, and per-service
runbooks in `docs/runbooks/`; this item stays open until every service is
`cut-over` and Phase 7 lands.
