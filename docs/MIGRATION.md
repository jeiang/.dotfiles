# Host-Native Services Migration Plan

Working plan for executing [ADR 0002](adr/0002-migrate-legion-to-host-native-services.md)
and [`IMPROVEMENTS.md` §4](IMPROVEMENTS.md). This document is the phased action
plan; each piece is sized to be implemented and verified independently. Live
cutover steps (volume moves, DNS changes, K3s teardown) are operator runbooks,
not repository automation.

Status legend: each piece is `todo`, `in-progress`, `done` (code merged), or
`cut-over` (verified live and old deployment removed).

## Confirmed Decisions

Decisions confirmed by the operator on 2026-07-19, extending ADR 0002:

- **Data retention**: NetBird, Pocket ID, Actual Budget, H@H, and Stirling PDF
  must retain their existing data (planned volume/state migrations). The
  monitoring stack and CrowdSec state may be reset. Attic already runs
  against an **external managed PostgreSQL** and has no local state (the
  `k8s-manifests` attic README describing a SQLite volume is stale — the
  Postgres DB was created from scratch and the SQLite→Postgres question is
  settled history, not a migration step); the flake carries only its
  connection-string secret. The host-native module reuses the live
  configuration as-is; runbook verification is push/pull against the
  existing cache.
- **Kubernetes-only concerns are dropped**, not migrated: ServiceAccounts,
  RBAC, Kyverno policies, the NetBird Kubernetes operator and
  `netbird-resources` chart, the Bitwarden Secrets Manager operator, the
  rclone CSI driver, cert-manager, Traefik, and the Hetzner CCM/CSI platform
  components.
- **Custom packages are flake outputs** under `modules/packages/`
  (`perSystem.packages.*`), consumed by modules via `self.packages.*` per the
  existing package-wrapper policy.
- **TLS strategy**: Caddy obtains a wildcard `*.jeiang.dev` (+ apex)
  certificate via ACME DNS-01 against Hetzner DNS, plus DNS-01 certificates
  for `aidanpinard.co` and `pinard.co.tt` (both hosted in Hetzner DNS).
  `noelejoshua.com` and `plyrex.dev` are **not** in Hetzner DNS; their hosts
  (`noelejoshua.com`, `pdf.plyrex.dev`, `jellyfin.plyrex.dev`,
  `seerr.plyrex.dev`) use HTTP-01/TLS-ALPN-01 (or on-demand TLS) issued at
  the Edge Node, which only succeeds after each host's DNS points at the
  Edge Node — the cutover runbook must cover this gap and the third-party
  DNS coordination.
  The NetBird reverse proxy needs `proxy.jeiang.dev` + `*.proxy.jeiang.dev`
  (a second-level wildcard NOT covered by `*.jeiang.dev`); prefer a DNS-01
  wildcard via Hetzner DNS delivered to it, falling back to its built-in ACME
  through the TLS passthrough if it cannot consume externally provided
  certificates.
- **NetBird reverse proxy placement**: it runs on a different node from the
  Edge Node so it can freely open custom ports. Caddy forwards
  `proxy.jeiang.dev` and `*.proxy.jeiang.dev` on 443 to it with **TLS
  passthrough** (SNI-based layer-4 routing; no termination at the edge).
- **Legion nodes become NetBird peers.** Today only artemis runs the NetBird
  client; peer-only services (Blocky DNS, raw VictoriaMetrics/VictoriaLogs)
  are reached through the operator's Kubernetes routing peer, which is being
  dropped. Node enrollment replaces it (piece 3.4).
- **CrowdSec posture**: the edge HTTP bouncer/AppSec integration is
  configured fail-open (a CrowdSec restart must not 503 the single-node
  edge; the cluster's fail-closed choice relied on HA AppSec replicas).
  Flagged for operator override at plan approval.
- **Alerting is retained**: vmalert + Alertmanager with the existing Discord
  webhook move with the monitoring stack (reset applies to stored data, not
  to alerting capability).
- Port conflicts from co-located services are acceptable; they are recorded
  in the placement table below rather than driving placement changes.

## Workload Inventory

Source of truth: `k8s-manifests` repository plus the three cluster-only
workloads noted in `IMPROVEMENTS.md` §4 (jkmn-website, Stirling PDF, the
Tailscale proxy routes).

| Workload | Public host(s) | State | Disposition |
| --- | --- | --- | --- |
| Caddy (replaces Traefik + cert-manager + LB) | all below | ACME material (Disposable but rate-limit-sensitive; declared, no Volume) | New edge service |
| CrowdSec (LAPI, agent, AppSec) | — | resettable | Composition over first-party `services.crowdsec` |
| NetBird server (management + signal, unified `netbird-server`) | `netbird.jeiang.dev`, STUN `stun.netbird.jeiang.dev` (UDP 3478) | **retain** | Custom local module |
| NetBird dashboard | `netbird.jeiang.dev` | none (static assets) | Served directly by edge Caddy |
| NetBird relay | `netbird.jeiang.dev` (WS `/relay`) | none | Custom local module |
| NetBird reverse proxy | `proxy.jeiang.dev`, `*.proxy.jeiang.dev` | ACME material (**retain if reused**) | Custom local module, non-edge node |
| Pocket ID (idp) | `auth.jeiang.dev` | **retain** | First-party `services.pocket-id` |
| Attic (jeiang/attic fork, OIDC) | `attic.jeiang.dev` | none locally (external Postgres + Mega S4) | First-party `services.atticd` + fork package output |
| Actual Budget | `budget.jeiang.dev` | **retain** (10 Gi) | First-party `services.actual` |
| Stirling PDF | `pdf.plyrex.dev` | **retain** (login DB) | First-party `services.stirling-pdf` |
| H@H (hath-rust) | direct TCP 8888 | **retain** (client login + 30 Gi cache) | `pkgs.hath-rust` re-export + thin module |
| Blocky DNS | internal (NetBird peers) | none | First-party `services.blocky` |
| Monitoring (VictoriaMetrics, VictoriaLogs, Grafana, vmalert, Alertmanager, log/metric agents) | `grafana.jeiang.dev` | reset allowed | Local composition module |
| website | `jeiang.dev`, `aidanpinard.co`, `pinard.co.tt` | none | Static from `inputs.website` served by Caddy |
| jkmn-website | `noelejoshua.com` | none | Static from new flake input `github:joshua-noel/portfolio` (its flake exposes the html/css/js), served by Caddy |
| bill-splitter | `bill-split.jeiang.dev` | none | Static/thin service served via Caddy (investigate build) |
| github-redirect | `github.jeiang.dev` | none | Caddy redirect rule |
| Tailscale proxy (jellyfin/seerr) | `jellyfin.plyrex.dev`, `seerr.plyrex.dev` | — | **Deferred**: edge Caddy serves a placeholder page; the cluster proxy dies with K3s teardown (downtime accepted); tailnet integration happens at a later date |
| Dropped: Traefik, cert-manager, Bitwarden SM operator, rclone CSI, Kyverno/RBAC charts, NetBird operator + `netbird-resources`, Hetzner CCM/CSI | — | — | Removed with K3s |

## Proposed Placement

Provisional until the capacity audit (piece 0.6) confirms fit against live
steady-state usage (nodes have ~2 GB RAM). Placement is encoded in the
Legion inventory (piece 0.1); every stateful service keeps authoritative
state on a directly mounted Hetzner Volume; every service gets a systemd
`MemoryMax` derived from the audit.

| Node | Role | Services | Port notes |
| --- | --- | --- | --- |
| `legion-node1` | Edge Node | Caddy (80/443 public, layer-4 SNI passthrough for `*.proxy.jeiang.dev`), CrowdSec LAPI+AppSec, static sites (incl. NetBird dashboard), github-redirect (Tailscale client deferred) | 80/443 public; blocked for other services |
| `legion-node2` | NetBird | NetBird server, relay (+STUN UDP 3478), NetBird reverse proxy (TCP 443 + free custom ports), Pocket ID (private HTTP behind Caddy) | 443 owned by NetBird RP; 3478/UDP relay; remaining ports free for RP custom ports |
| `legion-node3` | Observability | VictoriaMetrics, VictoriaLogs, Grafana, vmalert, Alertmanager, Blocky | 53 owned by Blocky on the node's NetBird address |
| `legion-node4` | Applications | Attic, Actual Budget, Stirling PDF, H@H | 8888/TCP public for H@H; tightest RAM fit — audit may move Stirling PDF |
| `legion-node5` | — | nothing (decommission target) | — |

DNS after cutover: public service hosts → `legion-node1` public IPs, except
`stun.netbird.jeiang.dev` → `legion-node2`, and H@H reached at
`legion-node4` public IP:8888. `proxy.jeiang.dev`/`*.proxy.jeiang.dev`
resolve to `legion-node1` (edge) and are passed through to `legion-node2`.
The per-node `nodeN.jeiang.dev` records are deploy-rs SSH targets and keep
pointing at their own nodes.

RAM notes carried from the cluster: Attic was tuned to fit a 512 Mi limit
(two concurrent NAR uploads, 128 MiB SQLite mmap in the old setup); carry
equivalent concurrency/memory tuning into the module config.

## Cutover Safety Rules

These gate every runbook; they implement IMPROVEMENTS §4's "verify backup
and restore behavior before removing the Kubernetes deployment":

- **Rule 1**: a retained-data service's Kubernetes release is removed only
  after its Restic backup (piece 2.1) has run **and a restore has been
  verified**.
- **Rule 2**: old PVCs/Hetzner Volumes are kept for a stated rollback window
  (default two weeks) after cutover; `hcloud-volumes` PVCs default to a
  `Delete` reclaim policy, so runbooks must retain/detach the backing Volume
  (or flip the PV reclaim policy) **before** deleting a release.
- **Rule 3**: irreversible platform actions (Hetzner LB deletion, K3s
  teardown, node5 deletion) happen only in Phase 7 after every service is
  `cut-over`.

## Phases

Each piece lists its deliverable and acceptance criteria. `nix flake check`
plus evaluation of all five hosts must pass for every piece; that criterion
is implied and not repeated. Pieces within a phase are ordered; phases 3–6
can interleave per-service once 0–2 land, subject to the safety rules.

### Phase 0 — Foundations

- **0.1 Legion inventory rework** (`modules/hosts/legion/`): extend the node
  inventory with service placement metadata: `edge` flag (exactly one),
  per-node service list, public hostnames, required Hetzner Volumes
  (name/mountpoint), per-service firewall openings, and `MemoryMax`
  values. Add evaluation checks: exactly one Edge Node; placements
  reference existing nodes; public hostnames unique; stateful services
  declare a Volume; Backup Set paths are a subset of declared persistent
  paths. K3s stays enabled on all nodes during migration.
  *Accept*: checks fail on synthetic violations (covered by
  `modules/checks.nix` tests or assertion messages), current config still
  evaluates.
- **0.2 Firewall re-enable**: turn the NixOS firewall on fleet-wide,
  deriving openings from inventory. Must explicitly enumerate the live
  K3s-era data path, not just the K3s control ports (6443/10250/8472
  already in `k3s.nix`): Traefik NodePorts targeted by the Hetzner LB and
  its health checks, STUN UDP 3478 direct node exposure, H@H hostPort
  8888, VXLAN/flannel, and private-interface (`enp7s0`) backend
  allowances.
  *Accept*: every node evaluates with `networking.firewall.enable = true`;
  the runbook stages enablement node-by-node with a live-traffic
  verification step per node (LB health, STUN, 8888) before proceeding to
  the next.
- **0.3 Custom Caddy package** (`modules/packages/caddy.nix`): Caddy built
  with `caddy-dns/hetzner` (DNS-01), CrowdSec bouncer HTTP + AppSec
  handlers, and `caddy-l4` (SNI passthrough), via `pkgs.caddy.withPlugins`
  with pinned versions, exposed as `perSystem.packages.caddy`.
  *Accept*: package builds in CI for `x86_64-linux`; `caddy list-modules`
  shows dns.providers.hetzner, layer4, and both CrowdSec handlers.
- **0.4 NetBird server-side packages**: reuse nixpkgs components where they
  match the deployed topology — `netbird-relay`, `netbird-proxy` (the
  reverse proxy), `netbird-dashboard` (≥ v2.90.2) — re-exported as
  `perSystem.packages.*`. The deployed management plane is the **unified
  config.yaml-driven `netbird-server`** (chart image
  `netbirdio/netbird-server:0.73.2`); nixpkgs has no unified `server`
  component, and the legacy split `netbird-mgmt` uses a materially
  different state layout, so build the unified server from the monorepo
  source (e.g. a `componentName`-style override of the nixpkgs netbird
  build; verify the pinned tag contains the unified server cmd). Do NOT
  substitute legacy `netbird-mgmt`.
  *Accept*: packages build in CI; versions ≥ chart-deployed versions
  (server 0.73.2, dashboard v2.90.2); unified-server binary confirmed to
  read the chart-style `config.yaml`.
- **0.5 hath-rust package**: re-export/pin `pkgs.hath-rust` (already in
  nixpkgs at ≥ 1.17.0) as `perSystem.packages.hath-rust`.
  *Accept*: builds in CI.
- **0.6 Capacity audit** (operator-assisted): record steady-state
  CPU/memory of every workload from the live cluster (VictoriaMetrics has
  the data) into this document; confirm or adjust the placement table and
  set per-service `MemoryMax`. Blocks the first service cutover, not code
  landing.
  *Accept*: placement table updated with measured numbers and final node
  assignments.

### Phase 1 — Edge Node (runs alongside K3s/Traefik until DNS cutover)

- **1.1 Caddy edge module** (`modules/nixos/edge/` or similar): Caddy on the
  Edge Node using `packages.caddy`. Hetzner DNS API token via sops. Certs:
  DNS-01 wildcard `jeiang.dev`/`*.jeiang.dev`, DNS-01 `aidanpinard.co`,
  `pinard.co.tt`; HTTP-01/on-demand TLS for `noelejoshua.com` and the
  `plyrex.dev` hosts. Layer-4 listener on 443 routing SNI
  `proxy.jeiang.dev`/`*.proxy.jeiang.dev` to `legion-node2:443` raw, all
  other SNI to local termination. Backend proxies point at private-network
  addresses from the inventory. NetBird routes need protocol care:
  h2c/gRPC backends for `/signalexchange.SignalExchange/`,
  `/management.ManagementService/`, `/management.ProxyService/`;
  WebSockets for `/ws-proxy/` and `/relay` (→ relay port); default →
  dashboard static assets; long read/stream timeouts (≥ 15 m, also for
  Attic NAR uploads). While Traefik still owns DNS, the module must be
  installable without traffic (verification via `curl --resolve`).
  *Accept*: config renders; `caddy validate` passes (as a check if
  feasible); route table covers every public host in the inventory
  including the protocol-specific NetBird routes.
- **1.2 Static sites on the edge**: serve `website` (from `inputs.website`,
  which gains a caller — amend `IMPROVEMENTS.md` §3), `jkmn-website` (new
  flake input `github:joshua-noel/portfolio`, whose flake exposes the
  html/css/js output), `bill-splitter` (investigate `jeiang/bill-splitter`
  build output; serve statically if possible, else thin service), the
  NetBird dashboard static assets, the `github.jeiang.dev` redirect, and
  placeholder pages for `jellyfin.plyrex.dev`/`seerr.plyrex.dev` (see
  1.4).
  *Accept*: each host serves correct content via `curl --resolve` against
  the Edge Node before DNS moves.
- **1.3 CrowdSec composition module**: build on first-party
  `services.crowdsec` — LAPI + log acquisition from Caddy access logs +
  AppSec component, bouncer key wiring into Caddy's CrowdSec handlers,
  Attic traffic exception, and exclusions for long-lived NetBird streams.
  **Fail-open posture** at the edge (see Confirmed Decisions) with
  explicit startup ordering (LAPI before Caddy handler activation). State
  is fresh (reset allowed).
  *Accept*: services start in a VM test or on-node; Caddy handler config
  references a valid LAPI URL + key from sops; a CrowdSec restart does not
  interrupt edge traffic.
- **1.4 Media routes — deferred**: the Tailscale-based backend for
  `jellyfin.plyrex.dev`/`seerr.plyrex.dev` is NOT migrated now. The edge
  serves a static placeholder page on both hosts (implemented in 1.2); the
  cluster's Tailscale proxy pod is deleted with the K3s teardown and its
  downtime is accepted. Joining the Edge Node to the tailnet and restoring
  the proxied routes (the accepted ADR 0002 exception) happens at a later
  date, after the migration.
  *Accept*: placeholder responses render for both hosts.
- **1.5 Runbook `docs/runbooks/edge-cutover.md`**: staged DNS cutover per
  host (test via `--resolve`, lower TTL, move A/AAAA records from the
  Hetzner LB to `legion-node1`, watch logs), third-party DNS coordination
  for `noelejoshua.com`/`plyrex.dev` and the HTTP-01 cert-issuance gap
  after their cutover, Hetzner Cloud Firewall changes, and LB removal
  criteria (Phase 7 only).

### Phase 2 — Backup Foundation (before any stateful cutover)

- **2.1 Restic backup module**: `services.restic.backups` to the Mega S4
  bucket with sops credentials; per-service Backup Sets (enabled as each
  service migrates) for NetBird, Pocket ID, Actual Budget, Stirling PDF,
  and H@H login data (cache excluded); SQLite-safe snapshot hooks where
  needed; Backup Set ⊆ declared persistent paths enforced by the 0.1
  check. Daily schedule, 30-day retention per IMPROVEMENTS §1.
  *Accept*: evaluates; check rejects a path outside persistence; restore
  procedure documented in `docs/runbooks/restore.md` and exercised once
  per service during its cutover (Safety Rule 1).

### Phase 3 — NetBird stack (data retained)

- **3.1 NetBird service module** (`modules/nixos/netbird-server/`): custom
  local module running the unified `netbird-server` (management+signal)
  and relay with STUN 3478 on `legion-node2`. Secrets via sops: store
  encryption key, relay auth secret, IdP session cookie key, proxy token
  (values migrated from Bitwarden SM by the operator). Auth note
  (discovered during 3.1): the chart configures NetBird's embedded IdP
  (`/oauth2` issuer + session cookie key); the Pocket ID federation is
  configured **at runtime in the GUI settings** (external OIDC provider),
  so it lives in the server's retained database and migrates with the
  state copy — nothing to wire in the module, but runbook 3.3 must verify
  Pocket ID-federated login still works after cutover (Pocket ID remains
  on the cluster at `auth.jeiang.dev` until Phase 4).
  Management URL stays `netbird.jeiang.dev:443`;
  artemis's existing client keeps working. Dashboard assets are served
  from the edge (1.2).
  *Accept*: module evaluates with state dir on a declared Hetzner Volume
  mount; firewall openings derived from inventory (3478/UDP, relay,
  private backend ports for Caddy).
- **3.2 NetBird reverse proxy module**: `netbird-proxy` on `legion-node2`
  bound on 443 (receiving the edge TLS passthrough), registered against
  the local management server with its proxy token, and running its own
  CrowdSec bouncer against the node1 LAPI over the private network (the
  edge bouncer never sees passthrough traffic). Preferred cert path: an
  externally provisioned `*.proxy.jeiang.dev` + `proxy.jeiang.dev` DNS-01
  wildcard (via `security.acme` + Hetzner DNS provider) if the proxy
  supports supplied certs; fallback: its built-in ACME (TLS-ALPN-01 flows
  through the edge passthrough), migrating existing ACME state.
  *Accept*: module evaluates; chosen cert path documented in the module;
  custom-port capability preserved; bouncer wired to LAPI.
- **3.3 Runbook `docs/runbooks/netbird-migration.md`**: quiesce the K8s
  NetBird server, back up then copy server state (and proxy ACME state if
  reused) from the PVC to the node2 Volume, move secrets from Bitwarden SM
  to sops, cut `netbird.jeiang.dev`/`stun.netbird.jeiang.dev`/
  `proxy.jeiang.dev` DNS, verify peer reconnection and proxy hosts, then
  (after Safety Rules 1–2) remove the K8s release and the NetBird
  operator/`netbird-resources`.
- **3.4 Legion nodes as NetBird peers**: import the existing NetBird client
  module (`modules/nixos/netbird.nix`) into `legionConfiguration` (or
  per-node via inventory) with sops setup keys, replacing the dropped
  Kubernetes routing peer for peer-only services. Guard against the
  bootstrap circularity: nodes must resolve `netbird.jeiang.dev` and reach
  the management plane via public DNS/upstream resolvers, never via
  Blocky-over-NetBird.
  *Accept*: evaluates; client DNS config does not depend on the tunnel
  being up; enrollment procedure in the runbook.

### Phase 4 — Identity (data retained)

- **4.1 Pocket ID module**: `services.pocket-id` on `legion-node2` behind
  Caddy at `auth.jeiang.dev`; state on a declared Volume; secrets
  (encryption key, SMTP credentials) via sops.
  *Accept*: evaluates; state path on Volume; backend route present in edge
  config.
- **4.2 Runbook `docs/runbooks/pocket-id-migration.md`**: back up, copy PVC
  data to the Volume (chown to the module's service user), move secrets,
  cut DNS with the edge, verify OIDC logins (Grafana, Attic, NetBird,
  kubectl users until K3s retires), then remove the K8s release per the
  safety rules.

### Phase 5 — Applications

- **5.1 Attic module**: `services.atticd` using the fork's server package
  (new flake output from `inputs.attic`, e.g.
  `perSystem.packages.attic-server`) on `legion-node4`; external managed
  PostgreSQL URL and Mega S4 credentials delivered via `environmentFile`
  (`ATTIC_SERVER_DATABASE_URL` etc.) so credentials never hit the store;
  carry the cluster-era concurrency/memory tuning; preserve the CrowdSec
  traffic exception on the edge route. Signing keys and cache URL
  unchanged.
  *Accept*: evaluates; no Volume required; route present; no secret in
  store-rendered config.
- **5.2 Actual Budget module** (retain data): `services.actual` on
  `legion-node4`, data dir on a declared Volume.
- **5.3 Stirling PDF module** (retain data): `services.stirling-pdf` with
  login enabled on `legion-node4` (audit may move it), data on a declared
  Volume (replacing the cluster-provisioned 10 GiB Volume).
- **5.4 H@H module** (retain data): thin module around
  `packages.hath-rust` on `legion-node4`; cache/login/download dirs on a
  declared Volume; public TCP 8888 opened on that node only.
- **5.5 Blocky module**: `services.blocky` on `legion-node3` on the node's
  NetBird address (requires 3.4), with systemd ordering on the NetBird
  client (or listen-all + firewall scoping to the NetBird interface);
  same blocklists/upstreams as the chart. Replica count drops 2→1 — peer
  DNS becomes a single point of failure (accepted; recorded here). The
  NetBird DNS zone's nameserver entry must be repointed to the new
  address (runbook 5.7). Expose raw VictoriaMetrics/VictoriaLogs on the
  node3 NetBird address the same way (replaces the dropped
  `NetworkResource`s).
- *Accept for 5.2–5.5*: evaluates; state on declared Volumes (where
  applicable); firewall openings scoped; edge routes present where
  public; service users own copied data (no blanket UID 1000 assumption —
  `services.actual`/`services.stirling-pdf` use their own users).
- **5.6 Runbook `docs/runbooks/apps-migration.md`**: per-service backup →
  copy (PVC → Volume, chown to the module's service user; UID/GID 1000
  only where the module is configured that way, e.g. H@H), secret moves,
  DNS/port cutover, verification, then release removal per the safety
  rules. Attic needs no data copy — deploy, verify push/pull against the
  external Postgres and existing cache keys, then remove the K8s release.
- **5.7 Runbook: NetBird DNS repoint** for the Blocky nameserver and
  VM/VL resource addresses (may fold into 5.6).

### Phase 6 — Monitoring (reset allowed)

- **6.1 Monitoring composition module** on `legion-node3`: VictoriaMetrics,
  VictoriaLogs, Grafana (Pocket ID OAuth via sops secret), **vmalert +
  Alertmanager with the existing Discord webhook (sops)**, vmagent/vlagent
  or journald-based log shipping from all nodes, scrape configs for the
  host-native fleet (Caddy, CrowdSec, NetBird, system metrics), and the
  CrowdSec dashboard. Fresh state on node3; one-month retention.
  *Accept*: evaluates; Grafana behind edge at `grafana.jeiang.dev`; scrape
  targets derived from the inventory; alert routes render.
- **6.2 Runbook `docs/runbooks/monitoring-cutover.md`**: deploy fresh, point
  DNS, verify dashboards/datasources/alerts, remove the K8s stack (old
  data discarded deliberately).

### Phase 7 — Decommission

- **7.1 Per-service K8s removal** happens inside each runbook above under
  the Cutover Safety Rules (a service is `cut-over` only after its release
  is deleted).
- **7.2 K3s removal**: after all services are `cut-over`, remove the K3s
  module import, kernel-module/sysctl leftovers no longer needed, K3s sops
  secrets, OIDC apiserver wiring, and `docs`/`DESIGN.md` references to the
  Experimental Cluster. Remove the Traefik/cert-manager/Bitwarden/CCM/CSI
  expectations from documentation.
- **7.3 `legion-node5` decommission**: verify it owns no workload or Volume,
  remove it from the inventory and `nixosConfigurations`/deploy nodes,
  update DESIGN.md system-roles table; operator deletes the server and the
  Hetzner LB (runbook `docs/runbooks/decommission.md`).
- **7.4 Docs sweep**: mark IMPROVEMENTS §4 done, fold enduring decisions
  into DESIGN.md/ADR; land ADR 0003 (below) if not done earlier.

### Cross-cutting documentation

- **ADR 0003 — Edge TLS and NetBird proxy topology**: records the DNS-01
  wildcard strategy, per-zone cert issuance split, layer-4 SNI passthrough,
  NetBird RP on a non-edge node, legion nodes as NetBird peers, the
  fail-open CrowdSec posture, and Attic's external PostgreSQL.
- CONTEXT.md gains no new roles unless review says otherwise (Edge Node
  already defined).

## Out Of Scope

- Live cutovers, data copies, DNS changes, Hetzner console operations — all
  operator runbook work, executed outside this session.
- Provisioning Volumes, servers, DNS zones, Hetzner Cloud Firewall rules
  (documented as prerequisites only).
- The external managed PostgreSQL for Attic and the media tailnet peer.
- Application source repositories (website, bill-splitter, attic fork).
- IMPROVEMENTS §2 (fail-fast rollouts) and §3 (unused inputs) except where
  the migration directly touches them (the `website` input becomes used).
