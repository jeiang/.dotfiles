# Infrastructure alternatives audit (2026-08-22)

Scope: the 4-node Hetzner Cloud NixOS fleet (~1.9 GiB RAM/node, host-native
systemd, no Kubernetes, strict `MemoryMax` caps per unit). Sources are
GitHub release pages, nixpkgs source, and current (2026) comparison writeups,
checked live rather than from training memory. Every module cited below was
read directly from this repo under `modules/nixos/` before judging it.

Legend: Priority 1 = do this soon, 5 = no action needed / explicit "keep".

---

## 1. Edge reverse proxy — Caddy

**Current**: `services.caddy` (`modules/nixos/edge/default.nix`), automatic
HTTPS, Cloudflare DNS-01 for the `jeiang.dev` wildcard + two standalone
domains, per-site JSON access logging routed to both a local rolling file
(CrowdSec's tail source) and journald→VictoriaLogs, Prometheus `metrics` on
a private-only listener, `trusted_proxies cloudflare` dynamic range refresh,
CrowdSec + AppSec handler directives wired per site block.

**(a) Better alternative?** No.
- Caddy 2.11.4 (2026-06-03) is actively maintained, repo pushed same-day as
  this audit. Idle ~30 MB RAM vs Traefik's ~50 MB idle / ~180 MB loaded —
  roughly 2-4x heavier under load on comparable hardware.
- Traefik's headline value (container/K8s service discovery, dynamic
  reconfig from labels) is irrelevant here: every backend is a static
  private IP declared in Nix, not a container label. Switching would trade
  real RAM for zero capability gain on a 1.9 GiB node.
- **Pangolin** (fosrl/pangolin) is not a reverse-proxy replacement — it's an
  identity-aware WireGuard tunnel product (Pangolin control-plane + Traefik
  + Gerbil + Newt) built for exposing services *behind NAT with no public
  IP*. Every Legion node already has a public IP and terminates TLS
  directly. Adopting it would mean running Traefik anyway (inheriting its
  heavier footprint), plus WireGuard tunnel machinery that duplicates the
  NetBird mesh already in place, for a NAT-traversal problem that doesn't
  exist here. Minimum documented footprint is ~1 GiB for the Pangolin stack
  alone — more than half a node's total budget. No NixOS module exists
  (nixpkgs has bare `fosrl-pangolin`/`fosrl-gerbil` packages, no
  `services.pangolin` unit) — a migration would mean hand-rolling four
  systemd units from scratch.

**(b) Hand-rolled wheels?** No. The module composes Caddy's own directives
(`crowdsec`, `appsec`, `log`, `tls { dns cloudflare }`) — this is exactly
what the upstream module and the CrowdSec bouncer plugin are for, nothing
reimplemented.

**(c) Missing?** Nothing edge-specific; see §11 (Anubis) for AI-scraper
mitigation, which sits in front of Caddy rather than replacing it.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 2. WAF / bot mitigation — CrowdSec

**Current**: `services.crowdsec` (`modules/nixos/crowdsec/default.nix`),
LAPI + AppSec engine, `crowdsecurity/caddy` + `crowdsecurity/appsec-virtual-patching`
hub collections, a hand-authored local AppSec config
(`jeiang/appsec-caddy`) that allow-lists NetBird's gRPC/WebSocket routes, a
custom `crowdsec-bouncers` oneshot unit that idempotently registers bouncer
keys via `cscli`, IP/CIDR whitelists for the Hetzner private network and
NetBird mesh, cache-traffic whitelist for garret's two hostnames, 512 MB
`MemoryMax`.

**(a) Better alternative?** No — keep CrowdSec.
- v1.7.8 (2026-05-11), repo pushed 2026-08-21 (day of this audit), 14.6k
  stars, two CVEs patched within the last release cycle and shipped
  promptly — this is a well-maintained project, not a stagnant one.
- fail2ban would be a **regression**: it has no crowd-sourced blocklist and
  no cross-node decision sharing, both of which CrowdSec already provides
  for free across the fleet. Comparisons put CrowdSec ahead on both
  detection signal and CPU efficiency under attack load.
- The 512 MB cap is not conservative headroom — AppSec + RE2 inspection
  realistically needs close to that much; do not shrink it.

**(b) Hand-rolled wheels?** Partially justified, one real gap: nixpkgs'
`services.crowdsec` module has **no declarative bouncer-key option** — there
is no `services.crowdsec.bouncers` in the nixpkgs module as of the pinned
release. The custom `crowdsec-bouncers` oneshot (idempotent `cscli bouncers
add` calls gated by `cscli bouncers list | grep`) is the documented
workaround and is reasonable; it is not something upstream currently
offers, so this isn't wheel-reinvention, it's filling a real module gap.
Flag to revisit if nixpkgs ever adds that option.

**(c) Missing? Complementary addition worth piloting: Anubis**
(TecharoHQ/anubis), a proof-of-work anti-scraper reverse-proxy hop purpose
built for the 2025-2026 AI-crawler traffic surge — a different problem than
CrowdSec's IP-reputation/exploit-signature model, and commonly deployed
alongside it rather than instead of it. v1.27.0 (2026-08-08), actively
maintained, and it has a mature NixOS module
(`services.anubis.<name>` in `nixos/modules/services/networking/anubis.nix`,
present in both 25.11 and 26.05). Caveat: an open upstream issue
(TecharoHQ/anubis#1349) reports nonzero idle CPU per instance rather than
near-zero-at-rest — verify actual idle RAM/CPU against this fleet's tight
`MemoryMax` caps before deploying fleet-wide; pilot it only on endpoints
actually seeing scraper load (e.g. the static sites) rather than every
Caddy site block.

**Verdict: KEEP CrowdSec.** Pilot Anubis as an addition, not a swap.
Migration effort: low (additive). Priority: 3.

---

## 3. DNS resolver / ad-blocking — Blocky

**Current**: `services.blocky` (`modules/nixos/blocky.nix`), custom port 553
(NetBird's own resolver holds 53), StevenBlack + hagezi denylists,
Prometheus metrics on the same HTTP listener, reachable only over the
NetBird mesh interface, 512 MB cap (real usage documented at ≤350 MiB).

**(a) Better alternative?** No — keep Blocky.
- v0.34.0 (2026-07-27), actively maintained (DNSSEC validation and RFC 2308
  SOA compliance landed recently), `services.blocky` present and current in
  nixpkgs.
- AdGuard Home is also well-maintained (v0.107.79, 2026-08-18) and has a
  mature `services.adguardhome` module, but for like-for-like blocklist
  size it runs roughly 2x Blocky's memory, and its main differentiators (web
  UI, per-client rules, DHCP) add nothing for a single operator whose config
  is already Nix-managed and who already has Grafana dashboards for the
  metrics AdGuard's UI would otherwise surface.
- Technitium DNS Server has a NixOS module (`services.technitium-dns-server`)
  but is a full authoritative+recursive+DHCP server — materially
  over-scoped for "ad-blocking resolver on a private mesh," and its
  nixpkgs packaging cadence lags its own upstream releases.
- dnsmasq is lighter but has no denylist ingestion or Prometheus metrics —
  strictly a downgrade from what's already running.

**(b) Hand-rolled wheels?** No — this is a first-party nixpkgs module
consumed directly, nothing reimplemented.

**(c) Missing?** Nothing specific to DNS.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 4. Mesh VPN — self-hosted NetBird

**Current**: `modules/nixos/netbird-server/default.nix`, a **custom** local
NixOS module (no nixpkgs first-party unified-server module exists) running
management + signal + relay + STUN as two systemd units on legion-node2,
OIDC via self-hosted Pocket ID, sqlite store, Volume-backed state with a
mount guard.

**(a) Better alternative?** No — keep self-hosted NetBird.
- This is the fleet's biggest existing custom-module surface (real secrets,
  a hand-rolled `config.yaml` render, mount-guard plumbing), so it's the one
  most worth scrutinizing — but the honest answer is that nothing beats it
  for this environment:
  - **Headscale** requires the proprietary-but-FOSS Tailscale client and is
    community-maintained by essentially one person (Juan Font Alonso);
    feature lag behind Tailscale's own client releases typically runs 3-12
    months, and there's no vendor to fall back on. It would trade one
    single-operator-maintained coordinator for another, without gaining
    anything — the current setup already runs the *official* NetBird
    server, not a reverse-engineered one.
  - **Tailscale SaaS** would genuinely reduce the operational surface (no
    self-hosted management/signal/relay/STUN at all) — worth naming
    honestly as the lowest-maintenance option — but it means every mesh
    packet's control plane (and, without a self-hosted relay override, some
    data-plane fallback traffic) depends on a third party's uptime and
    pricing for what is currently a fully self-hosted, zero-recurring-cost
    private network. Not recommended given the fleet's stated preference
    for self-hosted infrastructure, but flagged as the trade-off it is.
  - **Netmaker** and **Nebula** were both checked; neither offers a reason
    to move off a working, actively-maintained, already-integrated NetBird
    deployment (Nebula in particular lacks NetBird's dashboard/OIDC/ACL UI,
    which would be a functional regression, not a lateral move).

**(b) Hand-rolled wheels?** Justified. nixpkgs genuinely has no first-party
"unified NetBird server" module (only a split `netbird-mgmt`-style module
with a materially different state layout, per the module's own comment) —
the custom module is filling a real gap, not reinventing something upstream
already provides.

**(c) Missing?** Nothing specific.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 5. SSO / identity provider — Pocket ID

**Current**: `services.pocket-id` (`modules/nixos/pocket-id/default.nix`),
first-party nixpkgs module, OIDC-only passkey-based IdP, 256 MB cap, backs
NetBird dashboard, Grafana, garret's Pusher/Puller OIDC clients.

**(a) Better alternative?** No — keep Pocket ID.
- **Authelia** is not a fair substitute: it's a forward-auth gate, not an
  OIDC token issuer. Apps here (Grafana, garret) need to *receive* an OIDC
  access token — Authelia would need a real IdP behind it anyway, adding a
  layer rather than replacing one.
- **Kanidm** is actively maintained and has a genuinely mature NixOS module
  (`services.kanidm`, with `server.settings`/`client.settings`/`unix.settings`
  and OAuth2 provisioning) — but it's a full identity/directory platform
  (POSIX accounts, LDAP-compatible reads, RADIUS). None of that is needed
  here: this fleet needs OIDC SSO across roughly five self-hosted apps, and
  Pocket ID does exactly that with a fraction of the surface area. Adopting
  Kanidm would be scope creep, not a capability unlock.
- **Zitadel** claims a lighter footprint than Authentik (~512 MB minimum,
  single Go binary + Postgres) but still wants a real Postgres instance and
  its own docs recommend 4 vCPU/8 GiB for anything beyond evaluation —
  disproportionate for a 1.9 GiB shared node.
- **authentik** needs Docker Compose (server + worker + Postgres), ~300 MB+
  RAM minimum just for the app tier before counting Postgres — heavier and
  more moving parts than Pocket ID for equivalent OIDC-only coverage.

**(b) Hand-rolled wheels?** No. One real upstream limitation worth noting
(not a repo problem, a Pocket ID v2 limitation): the nixpkgs-pinned v2.10.0
binary dropped env-var-based SMTP config in favor of DB-backed
`AppConfigVariable` rows set through the admin UI — the module's own comment
already documents this correctly as something Nix cannot express for a
from-scratch setup. No action needed, just confirming the module's existing
comment is accurate.

**(c) Missing?** Nothing specific.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 6. Observability — VictoriaMetrics + VictoriaLogs + Grafana + vmalert + Alertmanager

**Current**: `modules/nixos/monitoring/default.nix`, all five services on
legion-node3, ~1.6 GiB combined `MemoryMax` budget, per-service Grafana
dashboards (hand-authored + vendored), blackbox-exporter synthetic probes,
journald→VictoriaLogs log shipping, Discord + Hermes webhook alert fan-out.

**(a) Better alternative?** No — keep the current stack.
- VictoriaLogs is documented at up to 30x less RAM and 15x less disk than
  Elasticsearch/Loki for equivalent log volume — this is already the
  resource-efficient choice, not a legacy one to move away from.
- **Grafana Alloy** is not a backend alternative to compare against at all —
  it's the *successor to Grafana Agent* (which reached EOL 2025-11-01), i.e.
  a collector/shipping agent, not a metrics/logs store. The fleet's existing
  `systemd-journal-upload`→VictoriaLogs pipeline and Prometheus-style scrape
  configs already do the shipping job Alloy would do; swapping in Alloy
  would add a new agent process without replacing anything, for no gain.
- **OpenObserve** unifies metrics/logs/traces in one binary, which is an
  attractive "fewer moving parts" pitch, but no current, credible resource
  comparison against VictoriaMetrics+VictoriaLogs was found, and it would
  mean throwing away the two vendored + several hand-authored Grafana
  dashboards already built and verified against this fleet's exact metric
  names — a real migration cost for an unproven resource win.
- **SigNoz** is ClickHouse-backed and historically documented as wanting
  several GiB of RAM minimum — not realistic on a shared 1.9 GiB node.

**(b) Hand-rolled wheels?** No — this is composition of first-party
nixpkgs modules (`services.victoriametrics`, `victorialogs`, `grafana`,
`vmalert`, `prometheus.alertmanager`, `prometheus.exporters.blackbox`),
exactly the intended integration pattern, not a reimplementation.

**(c) Missing — two real gaps:**
1. **Log-based alerting.** VictoriaLogs holds logs but the current vmalert
    rule groups are metrics-only (`up == 0`, disk/mem thresholds, failed
    systemd units, blackbox probes). vmalert now natively supports LogsQL
    alerting/recording rules against VictoriaLogs (`type: vlogs` at the rule
    group level, querying via `/select/logsql/stats_query`) — this is a
    2025-2026-era vmalert feature, not a new dependency. Since vmalert is
    already deployed and already points at this same VictoriaLogs instance,
    adding a `type: vlogs` rule group (e.g. repeated 401/403 bursts on
    auth.jeiang.dev, Caddy 5xx spikes not visible in the current metric-only
    rules) is a low-effort, in-stack addition, not a new tool.
    **Migration effort: low. Priority: 3.**
2. **Tracing is entirely absent.** No Tempo/OTel-trace pipeline exists.
    Given the fleet is a handful of independent, mostly-synchronous
    reverse-proxied services (not a deep microservice call graph), tracing's
    marginal value here is genuinely low — this is a reasonable "not worth
    adding" rather than a real gap. **Priority: 1 (skip).**

**Verdict: KEEP the stack; add LogsQL-based vmalert rules.** Priority: 3
for the log-alerting addition, 5 (no action) for the stack itself.

---

## 7. Backups — restic

**Current**: `services.restic.backups` (`modules/nixos/backups/default.nix`),
first-party nixpkgs module, daily timers with 4h randomized stagger,
per-service isolated S3 repos on Mega S4, 30-day `--keep-daily` retention,
`backupPrepareCommand`/`backupCleanupCommand` pause hooks for SQLite-backed
services (Pocket ID, Actual Budget), shared repo password + S3 credential
secrets.

**(a) Better alternative?** No — keep restic.
- Both restic (0.19.1, 2026-07-05) and Kopia (0.23.1, 2026-06-16) are
  actively maintained, but **Kopia has no NixOS service module** — adopting
  it would mean giving up the declarative `services.restic.backups`
  integration this fleet already relies on (per-service repos, pause hooks,
  timer staggering, sops-templated credentials) for hand-rolled systemd
  units, a strict downgrade in this specific (Nix-declarative) environment
  even though Kopia's dedup/GUI story is arguably nicer in isolation.
- Borgmatic/BorgBackup traditionally needs an SSH-reachable server-side
  `borg` binary rather than restic's native S3 support — worse fit for an
  S3-only (Mega S4) backup target.
- autorestic was not confirmed to be meaningfully alive in 2026 search
  results relative to restic/Kopia's release cadence — not investigated
  further given restic already covers the requirement natively.

**(b) Hand-rolled wheels?** No — first-party module used as intended.

**(c) Missing — two real gaps:**
1. **No automated restore-test / DR verification.** The current setup runs
    backups but nothing confirms they're actually restorable. Lightest-weight
    fix: a periodic (e.g. monthly) systemd timer per critical service running
    `restic check --read-data-subset=5%` (cheap integrity spot-check) plus a
    quarterly full `restic restore latest --target /var/tmp/restore-test`
    diffed against an expected file manifest, alerting via the existing
    Alertmanager/Discord/Hermes path on failure. This reuses infrastructure
    already in place (systemd timers, existing alert fan-out) — no new tool.
    **Migration effort: low-medium. Priority: 3.**
2. **S3 object-lock/immutability on the Mega S4 bucket was not confirmed.**
    Mega's S3-compatible API documentation does not clearly state Object
    Lock/WORM support in what's publicly indexed; this needs a direct check
    against Mega S4's own API docs or a support ticket, not assumed either
    way. Given this is a single-operator personal fleet (not an enterprise
    ransomware threat model, and restic's own repo format is
    append-mostly/content-addressed, which already limits blast radius from
    accidental deletion vs. mutation), this is a "worth a five-minute check,
    not worth blocking on" item. **Migration effort: low (just a
    support/doc check). Priority: 2.**

**Verdict: KEEP restic.** Add restore verification. Migration effort: n/a
for the tool itself. Priority: 3 (restore testing), 2 (object-lock check).

---

## 8. Secrets management — sops-nix

**Current**: `modules/nixos/sops/default.nix`, age-encrypted per-service
secret shards keyed to host SSH keys, no default sops file (forces explicit
`sopsFile` per secret — a deliberate design choice per the module's own
comment), `restartUnits` used consistently across every consuming module to
force restarts on rotation.

**(a) Better alternative?** No — keep sops-nix.
- agenix is also actively used community-wide, but it's narrower (age-only,
  one file per secret, no template/shard workflow) — this fleet's Secret
  Shard pattern (`docs/adr/0006`, many co-located secrets per service file)
  is exactly the scaling case sops-nix's YAML+template model handles better
  than agenix's one-file-per-secret model. Switching would be a straight
  downgrade in ergonomics for no capability gain.
- git-crypt is not a fair comparison — it's a transparent git filter, not a
  secret-templating/injection system; it doesn't do what sops-nix's
  `sops.secrets`/`sops.templates` machinery does (owner/permission control,
  systemd-integrated delivery, restart-on-rotation).
- Vault/OpenBao would mean running an actual server process (plus unseal
  key management) on a 1.9 GiB/node fleet for a single operator, when
  sops-nix needs **no running service at all** — static, git-committed
  ciphertext decrypted at activation time. This would add real operational
  surface (a new stateful service, its own backup/DR story, its own
  MemoryMax budget) to solve a problem sops-nix already solves statically.

**(b) Hand-rolled wheels?** No — first-party module, used as intended.

**(c) Missing?** Secret rotation has no scheduling/expiry tracking, but for
a single operator across a handful of secret shards, automating rotation
cadence is disproportionate tooling investment — a periodic manual review
(e.g. an entry in an existing runbook, checked during scheduled maintenance)
is the right-sized answer, not new tooling. **Priority: 1 (process note,
not a build item).**

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 9. Nix binary cache — garret

**Current**: `modules/nixos/garret/default.nix`, the operator's own
purpose-built Rust cache (`jeiang/garret`), adopted per `docs/adr/0013`
specifically to replace Attic — Pusher (OIDC-authenticated push, GitHub
Actions OIDC + Pocket ID) and Puller (anonymous substituter, 302-redirect
to presigned S3 URLs so NAR bytes never cross the edge) as two units over a
shared SQLite index, Prometheus metrics on both.

**(a) Better alternative?** No — keep garret; this was just adopted and the
reasoning still holds.
- Cachix (SaaS) remains a legitimate lower-maintenance alternative in the
  abstract, but self-hosting was a deliberate choice already made and
  documented (ADR-0013), and nothing about Cachix specifically has changed
  to revisit that call.
- harmonia and nix-serve/nix-serve-ng are both simpler Rust cache servers,
  but neither implements OIDC-authenticated push or S3-presigned-redirect
  NAR serving — the two features ADR-0013 specifically called out as
  garret's advantages over Attic. Adopting either would mean *losing*
  capability the fleet just gained.
- garret is confirmed to be a real, actively-structured project (MIT
  licensed, CI workflows, ADRs, spec docs, benchmarks) under active
  development by the same operator — there is no indication of it being
  abandoned or superseded by another project since its adoption.

**(b) Hand-rolled wheels?** No — this *is* the first-party solution the
operator built after concluding no upstream module fit.

**(c) Missing?** Nothing specific — `docs/adr/0013` already documents the
one known gap (CI builds `attic-client`/garret's own push client from
source until garret's own CI seeds a cache for itself) as accepted,
temporary technical debt, not a silent gap.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 10. Deployment tool — deploy-rs

**Current**: `serokell/deploy-rs` (`modules/deploy.nix`, `flake.nix`),
alongside disko, impermanence, nixos-facter, and hjem for the rest of the
provisioning story.

**(a) Better alternative?** No clear win; keep deploy-rs, but the maturity
of the alternatives is worth naming.
- deploy-rs itself is confirmed actively maintained and funded by Serokell —
  repo activity through 2026-08 (issues, commits, last update 2026-06-29),
  not abandoned. This matters because deploy-rs has had rockier maintenance
  periods historically; that concern does not currently hold.
- **Colmena** is a real, actively maintained alternative (nix-community
  fork, multiple maintainers) with parallel multi-host deploys and a
  simpler flake-output shape — a legitimate lateral option. But deploy-rs's
  headline feature, **magic rollback on failed activation** (health-checked
  activation with automatic revert), is real safety value for a 4-node
  fleet with no on-site operator to manually intervene if a bad deploy
  wedges a node — Colmena does not have an equivalent automatic-rollback
  story. Losing that for marginally simpler config isn't a clear win.
- **clan** (clan.lol/clan-core) is under genuinely active 2026 development,
  but it's a fundamentally different paradigm — a full peer-to-peer fleet
  framework with its own vars/secrets system, service modules, and
  provisioning integration (its own sops-nix/disko/nixos-anywhere wiring).
  Adopting it would mean rewriting substantial parts of this flake's
  secrets and provisioning story to fit clan's model, not a drop-in
  deploy-tool swap — disproportionate for a 4-node personal fleet that
  already has a working sops-nix + disko + impermanence stack built
  independently.
- Plain `nixos-rebuild --target-host` would drop magic rollback entirely —
  a real capability loss, not a simplification, for a remote-only fleet.
- Comin (pull-based GitOps) and krops were checked; neither offers a
  reason to move off a push-based, already-working, actively-maintained
  deploy-rs setup.

**(b) Hand-rolled wheels?** No — deploy-rs is used as a deploy tool, not
wrapped or reimplemented; `modules/deploy.nix` just wires `deployChecks`
into `nix flake check`, which is exactly the tool's intended CI hook.

**(c) Missing?** Nothing specific.

**Verdict: KEEP.** Migration effort: n/a. Priority: 5.

---

## 11. Cross-cutting patterns worth flagging (not a tool swap)

Reading every module surfaced one repeated **non-upstream** pattern, not a
missing-feature gap: the `ExecStartPre = "+install -d -o <user> -g <user> -m
0750 <dataDir>"` ownership-fix workaround appears near-identically in
`modules/nixos/garret/default.nix`, `modules/nixos/netbird-server/default.nix`,
and `modules/nixos/pocket-id/default.nix`, each with its own comment
re-explaining the same root cause (`systemd-tmpfiles-setup.service` isn't
ordered after a Volume's mount unit, so a `tmpfiles.rules` entry created by
the upstream module races the mount on first activation). This is not a
"reimplemented wheel" — it's a real, unavoidable Nix/systemd ordering gap
that no upstream module currently handles for Volume-backed state — but
it's duplicated three times with duplicated commentary rather than factored
into one `flake.lib` helper (there's already a `self.lib.mountGuard` helper
these same three modules all use for the *mount-wait* half of this problem;
the *ownership-fix* half is the copy-pasted part). Low-effort, in-repo
cleanup, not an infra decision. **Priority: 2 (minor, do during otherwise
touching one of these files, not worth a standalone change).**

---

## 12. Missing from the infra layer entirely

| Area | Real gap? | Recommendation | Effort | Priority |
|---|---|---|---|---|
| **Automatic dependency updates** | **No** — already solved. `.github/workflows/update-flake-inputs.yml` is a mature, working equivalent: scheduled weekly PRs for low-risk inputs (website/portfolio/bill-splitter), opt-in `workflow_dispatch` checkboxes for higher-risk inputs (nixpkgs, sops-nix, deploy-rs, garret, hermes-agent, etc.), signed commits via a dedicated bot GPG key, full-CI-gated PRs. This is comparable to what Renovate would provide, and Renovate's own Nix-flake support is immature by comparison — do not add Renovate. | n/a | 5 (no action) |
| **Vulnerability / CVE scanning of the Nix closure** | **Yes, real gap.** No scanning currently runs against the flake's closure. **vulnix** (`nix-community/vulnix`, maintainer @henrirosten) is actively maintained with 2026 issue-tracker activity, matches derivations in a build's transitive closure against the NVD, supports a whitelist file for accepted/false-positive CVEs, and outputs structured JSON — a real, practical fit for a CI job. `nix-security-tracker` (tracker.security.nixos.org) is a complementary *dashboard/record-linkage service* for nixpkgs-wide CVE tracking, not a per-closure scanner you'd run in this repo's CI — don't conflate the two. Grype/Trivy have no meaningful Nix-store awareness and are irrelevant here (no OCI images in this fleet). Concrete recommendation: add a non-blocking CI job that runs `vulnix --system` (or `-C` against each host's built toplevel) after the existing build steps in `ci.yml`, posting findings as a PR comment or job summary; keep it non-blocking initially given false-positive risk, revisit blocking once the whitelist is tuned. | Medium | 4 |
| **Status page** | **Partial / optional.** blackbox-exporter + Grafana already give the operator full visibility — a status page adds nothing for solo operational awareness. It's only worth it if the intent shifts to communicating uptime to other people who use these services (e.g. budget.jeiang.dev's other user, noelejoshua.com's owner). **Gatus** is genuinely lightweight (single Go binary, `services.gatus` present and actively updated in nixpkgs — recent PRs bumping 5.14→5.15 etc.) and could reuse the existing blackbox probe target list as its check config. Recommend only if there's an actual audience for it; not a default "add this." | Low (if wanted) | 2 |
| **Log-based alerting** | **Yes, real gap** — covered in §6 above (vmalert's `type: vlogs` LogsQL rules against the already-deployed VictoriaLogs). | Low | 3 |
| **Per-service healthchecks** | **No — already covered.** blackbox-exporter probes Pocket ID, Actual Budget, garret Puller/Pusher, and NetBird server over the private network, feeding `BlackboxProbeDown` in vmalert with per-target severity tiers. This is a solid, already-implemented answer to "per-service healthchecks." | n/a | 5 (no action) |
| **Secret rotation** | **Partial.** Covered in §8 — not worth automated tooling for a single operator; a periodic manual-review process note is the right-sized answer. | n/a | 1 |
| **Config drift detection** | **Mostly a non-issue.** Nix's declarative model structurally prevents the classic Ansible/Kubernetes drift problem — there's no imperative state to drift *from* except two things: (1) manual `ssh` intervention on a node bypassing the flake (a process/discipline risk, not a tooling gap — no tool detects "someone ran a command by hand" better than just not doing that), and (2) Volume-mounted service state (databases, uploads) which is expected to change independently of the Nix config and isn't "drift" in the harmful sense. No action recommended. | n/a | 1 |
| **Disaster-recovery testing** | **Yes, real gap** — covered in §7 above (periodic `restic check` + restore-and-diff verification). | Low-medium | 3 |
| **SBOM / vuln scanning** | Same finding as the CVE-scanning row above — vulnix covers this; no separate SBOM tool is needed on top of it for a fleet this size. | — | (folded into row above) |
| **CVE feeds** | Partially covered by adding vulnix to CI (row above); no separate feed-subscription tooling is warranted for a single-operator fleet — vulnix's NVD-backed scan on each build is the practical equivalent. | — | (folded into row above) |
| **Tracing** | **No — genuinely not worth it here.** Covered in §6; a handful of independent, mostly-synchronous services doesn't have a call graph deep enough to justify a trace pipeline. | n/a | 1 |
| **Agent framework (Hermes)** | **No — keep as-is.** Hermes is built on `NousResearch/hermes-agent`, an actively maintained, NixOS-packaged upstream module (native systemd mode, not a container), not a from-scratch custom framework — this is already "use the upstream module" done correctly, not a hand-rolled agent. No materially better self-hosted alternative surfaced for this specific "reads Telegram/alerts, executes fleet commands via a scoped SSH identity" shape. | n/a | 5 (no action) |

---

## Summary of action items, by priority

1. **Priority 4** — Add `vulnix` as a non-blocking CI job scanning each
    host's built closure against the NVD; this is the one area with no
    current coverage at all and an actively-maintained, ready-to-use tool.
2. **Priority 3** — Add `type: vlogs` LogsQL alerting rules to the existing
    vmalert config (auth-failure bursts, Caddy 5xx spikes) — pure config
    addition to infrastructure already running.
3. **Priority 3** — Add scheduled restic restore verification (`restic
    check --read-data-subset` monthly, full restore-and-diff quarterly),
    alerting through the existing Discord/Hermes path on failure.
4. **Priority 3** — Pilot Anubis in front of the highest-scraper-traffic
    static sites only, after confirming its idle RAM/CPU fits the fleet's
    caps (open upstream issue on idle CPU noted above).
5. **Priority 2** — Confirm whether Mega S4 supports S3 Object Lock; if
    not, treat as accepted risk given the personal-fleet threat model rather
    than switching providers.
6. **Priority 2** — Add a Gatus status page only if there's an actual
    external audience for one; otherwise skip.
7. **Priority 2** — Fold the three duplicated `ExecStartPre` ownership-fix
    blocks (garret, netbird-server, pocket-id) into one `flake.lib` helper
    alongside the existing `mountGuard`, next time one of those files is
    touched for another reason.
8. **Priority 1** — No action: secret rotation cadence, config drift,
    tracing, automatic dependency updates, and per-service healthchecks are
    all either already solved or not worth building for a single-operator
    fleet at this scale.

Every other area audited — Caddy, CrowdSec (core), Blocky, self-hosted
NetBird, Pocket ID, the VictoriaMetrics/Logs+Grafana stack, restic (core),
sops-nix, garret, and deploy-rs — is an explicit **keep**, confirmed against
current (August 2026) maintenance status and NixOS module availability.
