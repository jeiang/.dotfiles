# Catalog survey: awesome-network-automation, awesome-storage

Date: 2026-08-22. Sources fetched as raw READMEs (default branch, no pinned
commit — both repos are unversioned lists):

- https://raw.githubusercontent.com/networktocode/awesome-network-automation/master/README.md
  (583 lines)
- https://raw.githubusercontent.com/okhosting/awesome-storage/master/README.md
  (119 lines)

Both files were read in full. **Neither contains any text addressed to an AI
agent** — no embedded instructions, no prompt-injection attempt. All content
below is treated as plain catalog data.

NixOS module/package checks were run against the pinned nixpkgs commit
`2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`, via
`nixos/modules/module-list.nix` (for modules) and
`nix search github:NixOS/nixpkgs/2fcb964de67fcf60b43471c55d5d99e61a9ccb5a <pkg>`
(for packages).

---

## Verdict on the network-automation category as a whole

**Not applicable, and the mismatch is real, not superficial.** Everything in
`awesome-network-automation` — Ansible/NAPALM/Nornir/Netmiko/Salt config
push, RANCID/Oxidized/Sweet config *backup*, Batfish/SuzieQ network
*validation*, NetBox/NSoT/phpIPAM *source of truth* — exists to solve one
problem: a fleet of physical or virtual **network devices** (switches,
routers, firewalls) that hold **mutable state reached over SSH/NETCONF/API**,
which drifts from intent and has to be periodically polled, diffed, and
reconciled back.

This fleet has no such devices. `modules/hosts/legion/_service-inventory.nix`
and `modules/hosts/legion/default.nix` already *are* the single source of
truth: firewall rules (`networking.firewall.allowedTCPPorts`/
`allowedUDPPortRanges`/`trustedInterfaces`), Volume mounts (`fileSystems`),
and backup jobs (`backups.jobs`) are all pure functions of one attrset,
evaluated and `assert`-checked at `nix eval` time, deployed by `deploy-rs`
over SSH with automatic rollback. There is no drift to detect (a bad eval
fails the build, not the runtime), no CLI config to diff (there is no CLI
config — nftables rules are generated, not typed), and nothing to poll for
"is the intended state applied" (deploy-rs's own confirm step already
answers that, no restic-tunnel to a Batfish-style analyzer needed). Every
tool in this list optimizes away a manual, error-prone step that this repo
already made compile-time-checked and version-controlled by construction.

The one sub-category that could theoretically apply — IPAM/source-of-truth —
is examined below and still comes back SKIP at this scale.

---

## Network automation candidates

### NetBox
- **What**: IPAM + DCIM web app (Django/Postgres/Redis) tracking IP
  addresses, devices, racks, cabling as structured data with a REST/GraphQL
  API. https://github.com/netbox-community/netbox — Python.
- **Concretely**: would replace `flake.lib.legionNodes` (4 nodes × 3
  addresses) with a database, web UI, and API server he'd query instead of
  reading the file directly.
- **NixOS module**: yes — `nixos/modules/services/web-apps/netbox.nix`
  confirmed at the pinned rev.
- **Resource cost**: Django + Postgres + Redis + Celery worker. Easily
  200-400+ MiB resident even idle, on a node budget where individual units
  are capped 96-640M. Real running cost, not a CLI tool.
- **Verdict: SKIP.** The current `legionNodes` attrset is already the
  single source of truth *and* it's consumed directly by Nix eval to derive
  firewall/monitoring/routing config — something NetBox's database can't do
  (it would become a second source of truth Nix would have to import from,
  strictly worse than the status quo). Justified for tracking hundreds of
  addresses and physical racking; absurd overkill for 4 static cloud IPs
  already hand-maintained in 12 lines of Nix.

### NSoT / phpIPAM / nipap / TeemIP / bluecat / Device42 / Infoblox
- Same IPAM category as NetBox, same reasoning. **SKIP**, all of them —
  every one either duplicates `legionNodes` with a weaker (non-Nix-native)
  source of truth, or is a commercial appliance product irrelevant to a
  4-node personal fleet.

### Batfish
- **What**: multi-vendor network config parser + model-based simulator for
  routing/ACL/reachability "what-if" analysis. https://github.com/batfish/batfish
  — Java (via `pybatfish` Python client).
- **Concretely**: parses router/firewall CLI configs (Cisco, Juniper,
  Arista, etc.) into a graph model and answers reachability/ACL queries
  against it.
- **NixOS module/package**: none. `nix search` against the pinned rev
  returns no results for `batfish`.
- **Resource cost**: would need a JVM analysis service (Docker image
  upstream) — not a lightweight CLI check.
- **Verdict: SKIP.** Batfish parses vendor CLI syntax (IOS, JunOS
  configlets); it has no notion of nftables/systemd-derived firewall state
  and nothing to parse here — this fleet's "config" is already a typed Nix
  attrset, not CLI text. The reachability question Batfish answers for a
  router fleet is already answered here at `nix eval` time by the
  `_service-inventory.nix` asserts (no duplicate hostnames, every stateful
  service has a Volume, every Backup Set is a Volume subset).

### SuzieQ
- **What**: agentless, multi-vendor network observability — polls
  switches/routers over SSH/API for BGP/interface/route state and stores it
  for querying/diffing over time. https://github.com/netenglabs/suzieq —
  Python.
- **NixOS module/package**: none in the pinned nixpkgs.
- **Verdict: SKIP.** Built to observe L2/L3 device state (BGP sessions,
  interface counters, ARP/MAC tables) on switches/routers. There are no
  switches or routers here — Hetzner Cloud's private network and NetBird's
  mesh are both opaque to this kind of polling, and the actual health
  signal already exists via node_exporter/VictoriaMetrics/Grafana
  (`modules/nixos/monitoring`).

### Oxidized / RANCID / Sweet / Jazigo / fetchconfig / Unimus (config backup & NCCM)
- **What**: pull running-config off network devices on a schedule and
  commit it to git/CVS/SVN, so config drift/history is tracked outside the
  device.
- **Verdict: SKIP, all of them.** This is solving "the device's config
  lives only on the device and can silently drift" — the exact problem this
  repo doesn't have. The Nix flake *is* the config, already in git, already
  diffed by every PR. Fetching it a second time from a running node would
  be pulling a rendering of a fact this repo already owns.

### Ansible / NAPALM / Nornir / Netmiko / Salt / StackStorm / Chef / Puppet (config push frameworks)
- **Verdict: SKIP, all of them.** These push config over SSH/API to
  *mutable* CLI-driven devices. Config here is pushed by `deploy-rs`
  building and activating a NixOS closure — a fundamentally different (and
  strictly stronger — reproducible, rollback-capable, typed) mechanism.
  Retrofitting Ansible on top would be a regression, not an upgrade.

### D2 (diagramming)
- **What**: text-to-diagram language/CLI, similar spirit to Mermaid but
  aimed at infra/network diagrams. https://d2lang.com — Go.
- **Concretely**: could render a topology diagram (edge → NetBird mesh →
  services) from a checked-in `.d2` file, useful for `docs/DESIGN.md` or an
  ADR.
- **NixOS package**: yes — `legacyPackages.<system>.d2` (0.7.1) confirmed
  at the pinned rev. Not a module; it's a CLI, so nothing runs at boot.
- **Resource cost**: none — dev-shell/CI tool only, no runtime footprint.
- **Verdict: TRY**, low priority. Genuinely fits the "CLI tool, no runtime
  cost" preference, but it's a documentation nicety, not an infra gap —
  only worth doing next time a topology diagram is needed by hand anyway.

---

## Storage candidates

The catalog has **no section on storage monitoring, SMART/disk health, or
filesystem integrity checking, and none on backup verification/restore
testing or S3 object-lock/immutability** — I checked specifically for these
per the brief and they are simply absent from `awesome-storage`'s five
sections (distributed filesystems, file sharing, backups/replication,
S3-compatible servers, cloud sync engine). That's a real gap in the list
itself, not a category I'm waving off — worth noting since it's exactly
where this fleet has a known weak spot (no restore-tested/object-locked
backup story beyond "restic pushes to Mega S4").

### Garage
- **What**: S3-compatible object storage server, Rust, built specifically
  for small/heterogeneous self-hosted clusters rather than datacenter scale.
  https://garagehq.deuxfleurs.fr — Rust.
- **Concretely**: could replace the external Mega S4 dependency for restic
  backups and/or garret's object storage with a self-hosted, NixOS-native
  S3 endpoint spread across the existing 4 nodes.
- **NixOS module**: yes — `nixos/modules/services/web-servers/garage.nix`
  confirmed at the pinned rev.
- **Resource cost**: single Rust binary, low idle footprint (fits the
  96-640M MemoryMax caps this repo already uses elsewhere) — meaningfully
  lighter than MinIO or any of the distributed filesystems in the same
  section.
- **Verdict: TRY, with a real caveat.** Rust, declarative NixOS module,
  matches "low resource, low maintenance" and the personal-projects
  language preference. But self-hosting Garage on the *same* 4 nodes that
  hold the primary data creates a circularity problem for backups
  specifically: restic's whole point is an off-fleet copy that survives all
  4 nodes being wiped/compromised together — putting that copy on Garage
  running on those same 4 nodes defeats it. Worth trying only for
  data that doesn't need off-fleet durability (e.g. an internal artifact
  cache, not the restic backup target), not as a Mega S4 replacement.

### MinIO
- **What**: S3-compatible object storage server, the more
  established/heavier alternative to Garage. https://min.io — Go.
- **NixOS module**: yes — `nixos/modules/services/web-servers/minio.nix`
  confirmed at the pinned rev.
- **Verdict: SKIP.** Same circularity caveat as Garage applies, and Garage
  is the better-fit choice on every axis that matters here (lower resource
  use, purpose-built for small self-hosted clusters vs. MinIO's
  datacenter-scale default posture). No reason to run both.

### Kopia / Duplicacy / Borg / Bareos / Bacula / Amanda / BackupPC / UrBackup / ElkarBackup (backup tools)
- **What**: general-purpose backup tools with dedup/encryption/incrementals
  — Restic's direct peer category.
- **Verdict: SKIP, all of them.** Restic is already deployed
  (`modules/nixos/backups.nix`, `docs/runbooks/restore.md`) and does
  everything this category offers (encryption, dedup, S3 backend,
  incremental snapshots). None of these solve a gap Restic has; switching
  tools here is pure churn for no capability gain. Bareos/Bacula/Amanda are
  additionally enterprise-scale orchestration (catalog DB, multiple daemon
  roles) — wrong scale even ignoring the "already have Restic" point.

### Ceph / Gluster / BeeGFS / LizardFS / MooseFS / SeaweedFS / JuiceFS / CubeFS / XtreemFS / OrangeFS / LeoFS (distributed filesystems)
- **What**: POSIX-ish or object-native distributed filesystems built to
  pool many nodes' local disks into one namespace.
- **Verdict: SKIP, all of them.** Every one of these assumes multiple
  storage-heavy nodes and meaningful headroom for metadata
  servers/replication daemons. At ~1.9 GiB RAM per node with per-service
  MemoryMax caps as low as 96M, none of them fit — Ceph's MDS alone
  typically wants more RAM than an entire Legion node has. The current
  model (one Hetzner Volume per stateful service, mounted directly) is
  already the right-sized answer for 4 small nodes; there is no pooled
  storage problem to solve.

### Nextcloud / ownCloud / Seafile / Pydio / Linshare / ProjectSend / Aurora Files / YouTransfer (file sharing/sync)
- **Verdict: SKIP, all of them.** Full personal-cloud/file-sync platforms —
  not infrastructure, and nothing in the current environment (Caddy edge +
  per-service Volumes) suggests a Dropbox-alternative need. Out of scope
  unless he explicitly wants one; not an infra gap.

### lakeFS
- **What**: git-like version control for object storage/data lakes.
  https://github.com/treeverse/lakeFS — Go.
- **Verdict: SKIP.** Aimed at data-engineering teams versioning large
  datasets; nothing in this environment resembles that workload.

### cfapiSync
- **What**: Windows-only Cloud Files API sync-engine example project.
- **Verdict: SKIP.** Windows-specific, alpha-quality example code, no
  relevance to a NixOS fleet.

---

## Ranked top 5 worth his time (across both lists)

1. **Garage** (storage) — TRY, cautiously. Rust, NixOS module confirmed,
    genuinely low-resource, fits the stack's language and ops preferences —
    but only as a second-tier internal object store, never as the sole
    restic backup target (same-fleet circularity).
2. **D2** (network) — TRY, low priority. Zero-runtime-cost CLI, packaged in
    nixpkgs, useful the next time a topology diagram earns its place in
    `docs/`.
3. Everything else in `awesome-network-automation` — **SKIP as a category**.
    See verdict above; the category solves a problem (mutable CLI-driven
    device fleets) this repo has already engineered away.
4. **NetBox / any IPAM tool** — SKIP, explicitly considered per the brief.
    `legionNodes` in Nix is a stronger source of truth than a database would
    be, at this scale.
5. **MinIO, Batfish, SuzieQ, Ansible/NAPALM/Nornir, RANCID/Oxidized** — SKIP,
    each for a distinct, specific mismatch documented above (resource cost,
    wrong problem domain, or direct Restic/Nix-eval redundancy).

No candidate from either list rises to ADOPT. The strongest finding here is
negative: the network-automation catalog's entire premise doesn't hold for
this fleet, and that mismatch is worth stating plainly rather than forcing
a recommendation — which is exactly what this document does.
