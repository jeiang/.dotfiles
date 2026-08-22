# Self-hosted software catalog survey — awesome-selfhosted.net

Date: 2026-08-22
Source: [awesome-selfhosted/awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted) README.md (fetched directly, since the rendered HTML site is a JS SPA over the same data). Scanned all ~90 category sections. No prompt-injection content was found anywhere in the source — it's a plain categorized link list, no text addressed to an AI agent.

NixOS module verification is pinned to this exact nixpkgs commit, per instructions:
`2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`
Checked via `nixos/modules/module-list.nix` for real services, and `pkgs/by-name/<xx>/<name>/package.nix` for package-only entries (a 404 there doesn't 100% prove absence — nixpkgs has other package locations — but it's the standard path for anything added recently, so a miss is a real signal of "not readily available").

Environment recap: 4× Hetzner NixOS nodes at ~1.9 GiB RAM, host-native systemd, strict per-service `MemoryMax` (96M–640M), no k8s. Caddy + CrowdSec + NetBird + Pocket ID (OIDC) + Blocky + VictoriaMetrics stack + restic + Actual + garret + H@H + Hermes already running. Owner is a DevSecOps engineer who wants low-maintenance declarative Nix modules and OIDC SSO wherever practical.

---

## Network / Edge / Security

### Anubis
Anti-scraper "proof-of-work" gate that sits in front of a web app and blocks AI-scraper bots with a JS challenge before they hit your origin.
Repo: https://github.com/TecharoHQ/anubis · Go, single binary.

Why interesting: this owner already runs Caddy + CrowdSec at the edge. CrowdSec handles malicious-IP reputation; Anubis handles the different problem of AI scraper crawlers hammering a public site (garret, Hermes' KB, any blog) that aren't malicious per se but burn CPU/bandwidth. Complementary, not redundant.

NixOS module: **real service module** — `services/networking/anubis.nix`.
Resource cost: Go binary, no database, sits inline in the request path. Trivially fits under a 96M `MemoryMax`.
OIDC: not applicable — it's a bot filter, not an auth layer, and doesn't compete with Pocket ID.
**Verdict: TRY** — cheap to add in front of one public-facing service and see if it meaningfully cuts scraper noise; not urgent enough for an unconditional ADOPT.

### Warpgate
Multi-protocol bastion — proxies SSH, HTTPS, RDP, VNC, MySQL, Postgres, Kubernetes through one binary, with browser-based SSH/RDP/VNC access and no client-side software required.
Repo: https://github.com/warp-tech/warpgate · Rust, single binary.

Why interesting: currently SSH access to the 4 nodes is presumably direct/NetBird-mesh SSH. Warpgate would centralize session recording and give SSO-gated, browser-accessible SSH (useful from Zakkart or a phone without an SSH client) plus that it fronts Postgres/MySQL too — handy if you ever want ad-hoc DB access without punching more holes.

NixOS module: **real service module** — `services/security/warpgate.nix`.
Resource cost: Rust binary, single process, no external DB required (uses embedded SQLite for its own config/audit log). Should fit comfortably in a 128–256M cap.
OIDC: **confirmed** — native SSO support, references a dedicated SSO config page for OIDC providers.
**Verdict: TRY** — genuinely closes a gap (no session recording/audit trail on current SSH access today), and it's cheap and OIDC-native. Not an ADOPT only because current NetBird-mesh SSH access already works and this is a "nice to have" layer, not a fix for something broken.

### Numa
Rust DNS resolver: DNSSEC-validating recursive resolution, DoH/DoT/Oblivious DoH, ad-blocking, ephemeral overrides — single binary, positions itself against Blocky/Pi-hole/AdGuard.
Repo: https://github.com/razvandimescu/numa

Why interesting: only worth a mention because it's a *newer* alternative to the already-running Blocky. Nothing in its feature list (DNSSEC validation, Oblivious DoH) addresses a gap Blocky has for this setup.
NixOS module: absent (no module, no `pkgs/by-name` package at the pinned rev).
**Verdict: SKIP** — Blocky is already deployed and working; nothing here justifies a DNS migration.

### PlugNPiN
Auto-discovers labeled containers and creates DNS/CNAME entries in Pi-hole/AdGuard plus reverse-proxy hosts in Nginx Proxy Manager.
Repo: https://github.com/deepspace2/plugnpin · Go, Docker.

Why interesting: automates the exact "add a DNS entry + a proxy host" chore this owner does by hand for new services — but it's hard-wired to Pi-hole/AdGuard + Nginx Proxy Manager, neither of which is in use (Blocky + Caddy are). Would require forking/rewriting the integrations to be useful.
NixOS module: absent.
**Verdict: SKIP** — right idea, wrong integrations; not worth adapting for two tools this owner doesn't run.

---

## GenAI / Search / Data

### SearXNG
Privacy-respecting metasearch engine, aggregates results from other search backends, no tracking, no ads.
Repo: https://github.com/searxng/searxng · Python.

Why interesting: Hermes (the Telegram agent with git-repo KB) presumably needs a web-search capability at some point, and Ornith-1.0-9B on Artemis is local inference that could use a private search backend instead of routing to a commercial search API. SearXNG is the standard self-hosted answer for "give my agent stack a search tool without leaking queries to Google/Bing."

NixOS module: **real service module** — `services/searx.nix` (the module targets SearXNG specifically now that upstream Searx is archived).
Resource cost: Python/uWSGI app, modest — typically 100–200MB idle, spikes during aggregation. Should fit a 256M cap; Redis is optional (used for caching/rate-limiting, skippable at this scale).
OIDC: not built in — SearXNG expects to sit behind a reverse-proxy auth layer if you want to gate it, which Caddy + Pocket ID forward-auth can provide.
**Verdict: TRY** — direct fit for the Hermes/Ornith agent stack as a private search tool; genuinely new capability, not a dashboard.

### MeiliSearch
Typo-tolerant, instant full-text search API.
Repo: https://github.com/meilisearch/MeiliSearch · Rust.

Why interesting: full-text search (not vector/semantic — that's what the already-shortlisted Qdrant covers) is a different, complementary primitive. If Hermes' KB or Karakeep (already shortlisted) ever needs fast keyword search over notes/bookmarks rather than embedding similarity, MeiliSearch is the lightweight self-hosted answer.
NixOS module: **real service module** — `services/search/meilisearch.nix`.
Resource cost: Rust binary, single process, scales down well; fits a 128–256M cap for a personal-scale index.
OIDC: none — it's an API-key-gated service, not a login app; fine behind Caddy on the private mesh.
**Verdict: SKIP for now** — no concrete use case is defined yet (Karakeep and Qdrant already cover search/retrieval needs). Worth remembering as the answer *if* a keyword-search gap shows up later, but adding it speculatively is scope creep.

### GarageHQ
Geo-distributed, S3-compatible object storage.
Repo: https://git.deuxfleurs.fr/Deuxfleurs/garage · Rust.

Why interesting: an S3-compatible endpoint across the 4-node cluster could be a lighter-weight backend for anything currently needing object storage (backup targets, Actual Budget file exports, artifact storage for personal projects) than standing up MinIO or paying a cloud object-storage bill. Purpose-built for small multi-node deployments like this one.
NixOS module: **real service module** — `services/web-servers/garage.nix`.
Resource cost: Rust binary, modest at small scale, but it's a *storage* service — real cost is disk, not RAM; RAM footprint is reasonable (roughly 50–150MB per node) but needs to be provisioned on every node in the cluster to get its geo-distribution benefit, which is more topology commitment than the other candidates here.
OIDC: not applicable (S3 API uses access keys, not OIDC).
**Verdict: SKIP** — genuinely well-built and free of an obvious downside, but there's no stated need for extra object storage right now (restic backups already work; garret already serves as the Nix cache). Flagging it as the go-to answer if that need appears.

---

## Developer tooling

### Flipt
Self-hosted feature-flag platform — zero external dependencies by default, single Go binary.
Repo: https://github.com/flipt-io/flipt

Why interesting: for a DevSecOps engineer running personal Rust/Zig/Go/TS projects, feature flags are a normal thing to reach for once side projects get real users, and paying for LaunchDarkly for a personal project is silly. Flipt is the "no infra tax" option — no database required to start.

NixOS module: absent — no `services/*flipt*` module, no `pkgs/by-name/fl/flipt` package at the pinned rev.
Resource cost: single Go binary, would be trivial to run under a 96M cap even packaged manually.
OIDC: **confirmed** — "OIDC, JWT, OAuth, K8s Service Token, and API Token authentication methods supported out of the box."
**Verdict: TRY** — the value proposition is real and OIDC support means it slots into the Pocket ID setup cleanly, but the lack of a nixpkgs module means writing your own systemd unit + package derivation (or using the upstream Docker image with `virtualisation.oci-containers`, which sidesteps the module gap but breaks the "host-native systemd unit" pattern this cluster otherwise follows). Worth it only once an actual personal project needs flags — not worth pre-provisioning.

### GlitchTip
Sentry-compatible error tracking, self-hosted.
Repo: https://gitlab.com/glitchtip/glitchtip-backend · Python/Django + Celery.

Why interesting: error tracking across Hermes and other personal services would be genuinely useful — right now failures presumably surface only through VictoriaLogs greps, not structured error aggregation.
NixOS module: **real service module** — `services/web-apps/glitchtip.nix`.
Resource cost: this is the catch — GlitchTip needs Postgres, Redis, a web process, and Celery worker/beat processes. That's 4+ processes for one feature, and Django+Celery is not a light stack. Realistically 400–600MB+ once you provision headroom for all the pieces, eating a large slice of a single node's 1.9 GiB budget.
OIDC: unclear from docs (not confirmed either way in this pass — GlitchTip's SSO/SAML support has historically been split between community and paid-hosted tiers; would need to verify against the self-hosted OSS edition specifically before committing).
**Verdict: SKIP** — the idea is good but the resource bill (Postgres + Redis + Celery for a homelab-scale error volume) is disproportionate to the 640M cap ceiling on this cluster. Structured error tracking isn't worth a near-max-size service slot when VictoriaLogs already captures stderr/stdout.

### code-server / Coder
Browser-based VS Code, and a fuller remote-dev-environment platform respectively.
Repos: https://github.com/coder/code-server (Node.js) · https://github.com/coder/coder (Go).

Why interesting: could let you edit configs from a phone/tablet without a full dev environment, e.g. quick NixOS module tweaks from bed.
NixOS module: **both have real modules** — `services/web-apps/code-server.nix`, `services/web-apps/coder.nix`.
Resource cost: code-server alone is workable (~150–300MB idle, VS Code server is not tiny but survivable); Coder is a heavier orchestration platform (meant for managing multiple dev workspaces, arguably built for a team, not a solo user) — overkill here.
OIDC: Coder supports OIDC; code-server itself has no auth beyond a password, would need Caddy forward-auth via Pocket ID.
**Verdict: SKIP** — Zakkart (the darwin MacBook) and Legion already cover real development; this solves a problem ("I want to edit code from a device that isn't a real dev machine") that hasn't been stated as actually occurring. Not worth a node's memory slot speculatively.

---

## Network monitoring / homelab utilities

### Upsnap
Simple Wake-on-LAN dashboard — wake devices on your network, see current status.
Repo: https://github.com/seriousm4x/UpSnap · Go/Docker.

Why interesting: directly adjacent to the recent Artemis avahi work (the HomeKit WoL Switch Probe, per git history) — this is the same WoL problem from a different angle: a small self-hosted dashboard instead of a HomeKit-specific probe. Could either replace or complement that setup, or just be redundant with it — genuinely depends on what the avahi probe already covers, worth a look given the timing.
NixOS module: absent — no module, no `pkgs/by-name/up/upsnap` package at the pinned rev.
Resource cost: tiny Go binary, would be trivial under a 96M cap if packaged manually.
OIDC: no built-in auth beyond basic login; would sit behind Caddy/Pocket ID forward-auth if exposed at all (though WoL dashboards are typically LAN-only anyway).
**Verdict: SKIP, but flag for follow-up** — the recent avahi/HomeKit WoL probe (PR #124-era work) may already solve this exact problem; check what that covers before evaluating Upsnap, rather than adding a second WoL tool blind.

### NetAlertX / WatchYourLAN
Network presence/intrusion detectors — scan the LAN, alert on new/unknown devices.
Repos: https://github.com/netalertx/NetAlertX (GPL-3.0, Docker) · https://github.com/aceberg/WatchYourLAN (MIT, Go, exports to Grafana).

Why interesting: "new device joined the network" alerting is a real, low-effort security signal that nothing in the current stack (CrowdSec, NetBird) covers — those watch the mesh/edge, not the physical LAN. WatchYourLAN in particular is attractive since it already exports to Grafana, meaning it'd slot straight into the existing VictoriaMetrics+Grafana dashboard rather than becoming another isolated UI.
NixOS module: absent for both — no module, and no `pkgs/by-name` package for either at the pinned rev.
Resource cost: WatchYourLAN (Go) is light; NetAlertX (Docker, Python-ish stack per its architecture) is heavier and Docker-only, a worse fit for a "no Docker, host-native systemd" cluster.
OIDC: neither has it; these are LAN-facing tools typically not exposed past the local network at all.
**Verdict: TRY (WatchYourLAN specifically)** — genuinely fills a monitoring gap (unknown LAN devices) that the existing stack doesn't touch, exports natively into infra already built (Grafana), and is small enough to hand-package. NetAlertX is a SKIP in favor of it — same job, heavier stack, Docker-only.

---

## Personal utilities

### ClipCascade
Cross-device clipboard sync — Windows/macOS/Linux/Android, end-to-end encrypted.
Repo: https://github.com/Sathvik-Rao/ClipCascade · Java/Docker.

Why interesting: with Zakkart (macOS), Legion/Artemis (NixOS/Hyprland), and presumably a phone in daily use, clipboard sync across that heterogeneous set is a real quality-of-life gap that none of the current services address (Syncthing, already shortlisted, syncs files but not live clipboard).
NixOS module: absent — no module, no `pkgs/by-name` package at the pinned rev.
Resource cost: JVM-based service — this is the actual problem. A JVM process for clipboard sync is a heavy way to solve a small problem on a 1.9 GiB node; realistically 150–300MB+ just for the JVM baseline.
OIDC: none documented.
**Verdict: SKIP** — the use case is plausible but the JVM footprint is disproportionate, there's no nixpkgs packaging, and it's Docker-first. A lighter tool (or nothing, if the itch isn't strong) beats standing up a JVM service for clipboard sync.

### Wakapi
Self-hosted WakaTime-compatible coding-time tracker.
Repo: https://github.com/muety/wakapi · Go, SQLite by default.

Why interesting: for someone tracking personal project time across Rust/Zig/Go/TS work, this is a data-sovereignty swap for WakaTime with basically no downside — small Go binary, own data.
NixOS module: **real service module** — `services/web-apps/wakapi.nix`.
Resource cost: Go + SQLite, minimal — fits comfortably under a 96–128M cap.
OIDC: **confirmed** — "supports login via external identity providers via OpenID Connect," including disabling local auth entirely for SSO-only.
**Verdict: TRY** — cheapest possible add (real module, OIDC-native, tiny footprint) for a real personal habit (tracking coding time across languages/projects), if that's actually a habit worth tracking. Not an unconditional ADOPT only because it's a "nice to have," not solving a stated pain point.

### Domain Locker
Domain-name portfolio tracker — expiry dates, DNS records, WHOIS, uptime.
Repo: https://github.com/lissy93/domain-locker · Deno/Docker.

Why interesting: a DevSecOps engineer running a personal cluster with multiple domains (jeiang.dev, jeiang.vpn, whatever fronts the public services) has a real "did a domain silently expire" risk that nothing here currently tracks — Gatus (already shortlisted) monitors uptime, not domain/cert expiry portfolios.
NixOS module: absent — no module, no `pkgs/by-name` package at the pinned rev.
Resource cost: Deno runtime, moderate — likely 100–200MB, and Docker-first packaging (no clear standalone binary path).
OIDC: not confirmed in this pass.
**Verdict: SKIP** — the underlying need (catch expiring domains) is real, but this is solvable more cheaply: a Gatus check or a cron job hitting WHOIS is a 20-line script, not a new service. Standing up a Deno app for domain-expiry tracking is disproportionate.

---

## Notable but not for him (interesting, correctly out of scope)

- **Ghostfolio** (wealth/stocks/crypto tracker, TypeScript/NestJS, OIDC-confirmed) — legitimately different from Actual (which does budgeting, not investment tracking), but needs Postgres+Redis, and there's no signal this owner wants investment tracking specifically. A real gap in the catalog, not a rejection of the tool.
- **Docmost** (AGPL wiki/docs, Nodejs, alternative to Confluence/Notion) — worth naming because it's the most credible replacement if the already-rejected Outline verdict is ever revisited; AGPL-3.0, self-hosted, no catalog-standout reason to reopen that decision now.
- **Pangolin** (identity-aware tunneled reverse proxy, WireGuard-based, positions against Cloudflare Tunnel/Tailscale) — directly overlaps NetBird+Caddy, which already do this job. Not a gap, just a different implementation of a solved problem.
- **Teleport** (SSH/K8s/DB access plane + CA, Go) — the "enterprise" version of what Warpgate does at a fraction of the operational weight; wrong scale for 4 personal nodes.
- **IT-Tools** (static dev-utility toolbox — hashers, converters, generators) — genuinely handy, but it's a bookmarklet-grade convenience, not something worth a systemd unit; better served by the hosted demo or a local static file if wanted at all.

---

## Top 8 worth his time (ranked)

1. **Warpgate** — closes an actual gap (SSH session audit/recording, browser access, DB bastion) with OIDC baked in and a real nixpkgs module. Highest value-to-effort ratio here.
2. **Anubis** — near-zero cost, real nixpkgs module, complements CrowdSec instead of duplicating it.
3. **SearXNG** — the natural private-search backend for the Hermes/Ornith agent stack; real module, fits the "own your data" pattern already established.
4. **WatchYourLAN** — fills a monitoring gap (unrecognized LAN devices) the current CrowdSec/NetBird stack doesn't cover, and plugs straight into existing Grafana.
5. **Wakapi** — trivial cost, real module, OIDC-native; adopt if coding-time tracking is actually wanted, skip if it isn't.
6. **Flipt** — best-in-class feature-flag tool for personal projects, OIDC-confirmed, but no nixpkgs module means manual packaging — do this only once a project needs flags.
7. **Upsnap** — hold pending a check of what the recent avahi/HomeKit WoL work already covers; may be entirely redundant.
8. **MeiliSearch** — real module, cheap, but no defined use case yet; the answer to remember if full-text search over Karakeep/Hermes data becomes a want.

## Nothing good found here

- **DNS**: catalog has nothing that beats the already-running Blocky (Numa is interesting engineering, not a reason to migrate).
- **Backup**: the awesome-selfhosted README itself just redirects to awesome-sysadmin for this category — no direct entries to evaluate at all.
- **Object storage / distributed filesystems**: GarageHQ is well-built but there's no stated storage gap it fills; nothing else in the category (SeaweedFS, Zenko, Harbor) is a better fit for a 4-node 1.9 GiB cluster.
