# Catalog survey: awesome-sysadmin + awesome-status-pages

Date: 2026-08-22. Sources surveyed:

1. https://sysadmin.awesome-selfhosted.net/ (rendered site) plus the underlying data at
    `https://raw.githubusercontent.com/awesome-foss/awesome-sysadmin/master/README.md` (41 categories,
    fetched in full and grepped systematically — see method note at the end).
2. https://github.com/ivbeg/awesome-status-pages (OPENSOURCE + SERVICES tables, fetched in full).

NixOS module claims below were verified against this exact pinned nixpkgs rev (not master):
`2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`, via
`curl -sL ".../module-list.nix" | grep -i <name>`.

## Flag: text addressed to an AI agent

The awesome-status-pages README contains a contributor note: *"For contributors: AI-generated pull
requests are not permitted. Any automated PR will lead to a permanent ban, and the proposed service
will not be considered."* This is a repo contribution policy, not an instruction aimed at this task
(no PR is being filed) — noted per instructions and not acted on further.

No other AI-directed text was found on either source.

---

## Gap coverage: honest result

Of the six known gaps, the two catalogs only offer real candidates for **two**:

- **No DR restore-testing / backup verification** → Healthchecks (dead-man's-switch / cron monitoring)
- **No log-based alerting** → reaction (log-pattern-triggered daemon)

For the other four gaps, neither catalog has anything on point:

- **CVE/vulnerability scanning**: the only hit is Wazuh, and it's a full XDR/SIEM (see below), not a
  CI-integrable scanner. Neither list has anything resembling Trivy/Grype/OSV-Scanner-class tools —
  awesome-sysadmin has no "Security" category at all.
- **S3 object-lock / backup immutability**: not covered by any entry in either catalog. This is a
  bucket-configuration concern (Mega S4 / restic `--repack-*` flags), not a tool gap these catalogs
  would fill.
- **Secret rotation tracking**: no hits in either catalog.
- **Config drift detection**: closest tangential hit is Rudder ("patching, security & compliance," a
  CFEngine-based CM platform with drift-remediation baked in), but it's a full agent+server CM system,
  not a drift *detector* you'd bolt onto NixOS declarative config — see verdict below.

This is worth knowing on its own: these gaps will need sourcing outside these two lists.

---

## Candidates considered

### From awesome-sysadmin

**1. Healthchecks** — dead-man's-switch monitoring for cron jobs and scheduled tasks.
Repo: https://github.com/healthchecks/healthchecks · Python (Django), BSD-3-Clause.
- Gap filled: DR restore-testing / backup verification. Point a restic backup+`restic check`+restore-drill
  script at a Healthchecks check; it alerts the moment a scheduled backup or verification job stops
  reporting in, which is closer to real DR coverage than "the restic timer exists."
- NixOS module: **real service module** — `services/web-apps/healthchecks.nix` (verified at pinned rev).
- Resource cost: Django app + SQLite/Postgres + a scheduler; light but not free — plan on the low end
  of your MemoryMax range (~128–192M). Fits a 1.9 GiB node easily alongside existing services.
- **Verdict: TRY.** Directly fills a named gap, has a real module, modest footprint.

**2. reaction** — lightweight daemon that scans program/log output for repeated patterns and takes action.
Repo: https://framagit.org/ppom/reaction · Rust, AGPL-3.0.
- Gap filled: log-based alerting. vmalert only alerts on metrics; reaction can tail VictoriaLogs output
  (or raw journals) and fire on textual patterns — CrowdSec ban storms, repeated auth failures, OOM
  kills — closing the exact gap named.
- NixOS module: **real service module** — `services/security/reaction.nix` (verified at pinned rev).
- Resource cost: Rust, no runtime beyond itself — trivially fits a 96M MemoryMax cap.
- **Verdict: ADOPT.** Small, has a module, Rust (matches your stack preference), fills a named gap with
  near-zero resource cost. Best single find in either catalog.

**3. Backrest** — web UI and orchestrator for restic backups.
Repo: https://github.com/garethgeorge/backrest · Go, GPL-3.0.
- Adds: a browsable UI/scheduler on top of restic (which you already run declaratively via Nix).
- NixOS module: **absent** — grep hits `pgbackrest.nix`, which is the unrelated PostgreSQL tool
  pgBackRest, not this Backrest.
- Resource cost: small Go binary + web UI, but it's a new standing service for something you already
  automate via systemd timers.
- **Verdict: SKIP.** No module, and restic is "keep-as-is" — a UI wrapper doesn't clear the bar for
  adding a new persistent service.

**4. Wazuh** — unified XDR/SIEM, includes a CVE-feed-based vulnerability detection module.
Repo: https://github.com/wazuh/wazuh · C, GPL-2.0.
- Gap touched: CVE scanning (its vulnerability-detection module is the only genuine hit for this gap
  in either catalog) and log-based alerting (it's also a SIEM).
- NixOS module: **absent**.
- Resource cost: needs an Elasticsearch/OpenSearch-class backend under the hood — multiple GB minimum,
  nowhere close to a 1.9 GiB node's budget, even split across the cluster.
- **Verdict: SKIP.** Real capability, wrong shape entirely for this hardware.

**5. Rudder** — CFEngine-based configuration management with built-in patching/compliance/drift handling.
Repo: https://github.com/Normation/rudder · Scala, GPL-3.0.
- Gap touched: config drift detection (closest thing to it in either catalog).
- NixOS module: **absent**.
- Resource cost: JVM/Scala server + agents on every node — heavy, and it would mean adopting an
  imperative CM layer on top of (or instead of) your existing declarative Nix flake, which is a much
  bigger architectural bet than "add a drift checker."
- **Verdict: SKIP.** Wrong tool for a fleet that's already declaratively defined; NixOS's own
  `nixos-rebuild build` diff against deployed generation is a cheaper drift signal than adopting Rudder.

**6. GoAccess** — real-time web log analyzer/viewer (terminal or browser).
Repo: https://github.com/allinurl/goaccess · C, MIT.
- Adds: ad-hoc analysis of Caddy access logs (top paths, response codes, bandwidth) — not alerting, but
  useful for on-demand triage.
- NixOS module: **absent** (package-only in nixpkgs, not a module).
- Resource cost: essentially none — CLI tool, run on demand.
- **Verdict: TRY.** Free to add as a package (no service, no MemoryMax cap needed), useful during
  incident triage even though it doesn't address any gap directly.

**7. Loki** — Grafana's log aggregation system.
Repo: https://github.com/grafana/loki · Go, AGPL-3.0.
- NixOS module: real module exists (`services/monitoring/loki.nix`), but irrelevant here.
- **Verdict: SKIP.** Directly redundant with VictoriaLogs, which is already deployed and decided.

**8. Databasus** — Postgres/MySQL/MariaDB/MongoDB backup tool with web UI and external storage targets.
Repo: https://github.com/databasus/databasus · Docker, Apache-2.0.
- **Verdict: SKIP.** restic already backs up at the filesystem level (covers DB dump files if you
  produce them); a second, DB-specific backup tool duplicates that without adding coverage you lack.

**9. BorgBackup** — deduplicating archiver, restic's closest peer.
Repo: https://github.com/borgbackup/borg · Python, BSD-3-Clause.
- Noted per instructions as a "genuinely better alternative?" check on restic (keep-as-is). It isn't:
  Borg lacks restic's native S3-compatible backend maturity and you'd be trading a working, already-
  automated setup for a lateral move. Bar not met.
- **Verdict: SKIP (no re-pitch of restic decision).**

**10. Consul / etcd** (Service Discovery category) — not a named gap, and NetBird mesh + static Nix
config already give you service addressing. **Verdict: SKIP** — solves a problem you don't have.

**11. Sensu** (Monitoring category) — general infra monitoring. Fully redundant with the
VictoriaMetrics+Grafana+vmalert+Alertmanager stack you already run. **Verdict: SKIP.**

**12. Oxidized** — network device config backup tool (Ruby).
Repo: https://github.com/ytti/oxidized. Targets router/switch config snapshots (RANCID-style). You
don't run a fleet of network devices to back up — this solves someone else's inventory problem.
**Verdict: SKIP.**

### From awesome-status-pages (compared against Gatus, already decided)

Gatus (already shortlisted) has a real NixOS module: `services/monitoring/gatus.nix`, verified at the
pinned rev. None of the alternatives below do — that alone reinforces the existing pick for a
Nix-flake-managed fleet.

| Candidate | Lang/stack | NixOS module | Note vs. Gatus | Verdict |
|---|---|---|---|---|
| **Kener** (kener.ing) | Node.js/SvelteKit | absent | Nicer incident-management UI, but adds Node.js + DB runtime for a feature Gatus doesn't need (you don't run public incident comms) | SKIP |
| **Tinystatus** | Shell, static-page generator | absent | Genuinely zero runtime — a cron job writing static HTML. Interesting as a *front end* on top of Gatus's JSON output, not a replacement | SKIP (not worth swapping; could revisit as an add-on later) |
| **cState** | Hugo static site | absent | Needs external hosting (Netlify/Pages) and a separate check mechanism; doesn't self-host cleanly on your fleet | SKIP |
| **Upptime** | GitHub Actions + Pages | absent | Zero server cost, but your status/uptime data would live in a public GitHub repo — wrong trust boundary for internal infra | SKIP |
| **KuvaszUptime** | Kotlin/JVM + Postgres | absent | JVM + DB is heavier than Gatus for equivalent SSL/uptime checks | SKIP |
| **Vigil** | Rust | absent | Decent lightweight option, but no capability Gatus lacks; bar for switching not met | SKIP |
| **Peekaping** | Go/TS, Uptime-Kuma-style | absent | Same category as the already-rejected Uptime Kuma (no confirmed OIDC, unproven maturity) | SKIP |
| **HertzBeat** | Java | absent | Agentless monitoring platform, Prometheus-adjacent — overlaps VictoriaMetrics stack, heavier than needed for status-page duty | SKIP |

No alternative clears the bar against Gatus; the existing decision stands.

---

## Ranked top 8 (across both catalogs)

1. **reaction** — ADOPT. Fills log-based-alerting gap directly, has a real NixOS module, Rust, near-zero
    footprint.
2. **Healthchecks** — TRY. Fills DR/backup-verification gap directly, has a real NixOS module, modest
    footprint.
3. **GoAccess** — TRY. Zero-cost CLI, package-only, useful for Caddy log triage even without a module.
4. **Gatus (reconfirmed)** — no change; catalog survey reinforces it's the right call (only status-page
    option with a real NixOS module).
5. **Backrest** — SKIP but closest runner-up if you ever want a restic UI; revisit if a module appears.
6. **Wazuh** — SKIP for this hardware, but flag as the one tool in either catalog that does real
    CVE-feed vulnerability detection — worth remembering if you ever get a beefier node.
7. **Rudder** — SKIP; the only drift-adjacent hit, but wrong architecture for a declarative Nix fleet.
8. **Loki** — SKIP; redundant, but worth knowing the catalog's log-aggregation answer is a straight
    VictoriaLogs competitor, not something novel.

## Bottom line

Two adoptable finds, both cheap and both NixOS-module-backed: **reaction** (log-based alerting) and
**Healthchecks** (backup/DR verification signal). GoAccess is a free CLI add for log triage. Gatus's
status-page pick is reconfirmed as correct — nothing in awesome-status-pages beats it, and it's the only
one with a NixOS module. The three hardest gaps (CVE scanning, S3 object-lock, secret rotation) go
unfilled by both catalogs; that's a real finding, not a missed search — source them elsewhere (e.g.
CI-integrable scanners like Trivy/Grype, which don't appear in awesome-sysadmin's category list at all).

---

*Method note: awesome-sysadmin's rendered site groups entries under ~41 categories; the full raw README
(818 lines) was fetched and grepped by category and by keyword (`vulnerab|CVE|drift|rotat|secrets|vault|
trivy|grype|wazuh|sops` etc.) to confirm no dedicated Security category or drift/rotation tooling exists,
rather than relying on the rendered page's category excerpts alone.*
