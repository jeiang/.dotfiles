# Self-hosted application candidates for legion-node1..4

Research date: 2026-08-22. Environment: 4x Hetzner Cloud NixOS nodes, ~1.9 GiB RAM
each, small vCPU counts, 40 GB root + small attached Hetzner Volumes (10-40 GiB),
host-native systemd units declared in a Nix flake (no k8s), every service capped
with `MemoryMax` in the 96M-640M range. Already running: Caddy, CrowdSec, NetBird
(mgmt/signal/relay + reverse proxy), Pocket ID (OIDC SSO), Blocky, VictoriaMetrics +
VictoriaLogs + Grafana + vmalert + Alertmanager, Restic, Actual Budget, garret,
H@H, Hermes (Telegram agent with a git-repo knowledge base). Jellyfin + Jellyseerr
already run elsewhere (`jellyfin.plyrex.dev`, `seerr.plyrex.dev`). A Caddy hostname
`github.jeiang.dev` already exists, implying git-forge intent. Separate desktop
"Artemis" runs llama.cpp/llama-swap, Steam, Sunshine.

Numbers marked **GUESS** are extrapolated/estimated, not sourced from a specific
report. Everything else is backed by a cited source found in research (GitHub
issues/discussions, official docs, nixpkgs, r/selfhosted-adjacent blogs).

## Read-it-later / bookmarking

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Karakeep](https://github.com/karakeep-app/karakeep) (formerly Hoarder) | TS/Node + Meilisearch + optional headless Chromium | Core app ~200 MB, Meilisearch ~100 MB, Chromium crawler spikes to ~500 MB during archiving | No nixpkgs module found (Docker-only) | Yes — generic OIDC via `authelia`-style config, documented at docs.karakeep.app | TIGHT (300-800M with search+crawler) | 4 — best all-in-one bookmarks+notes+AI tagging, but heavier than the others |
| [Linkding](https://github.com/sissbruecker/linkding) | Python/Django | Lightest of the bunch, described as running comfortably on a Raspberry Pi (**GUESS** ~80-150M) | No dedicated nixpkgs module found; Docker-only | Supports OAuth/OIDC via reverse-proxy header auth or third-party integration | FITS | 4 — dead simple, low maintenance, does exactly bookmarking and nothing else |
| [Linkwarden](https://github.com/linkwarden/linkwarden) | TS/Next.js + Postgres + headless browser archiving | Heavier than Karakeep per comparison articles; DB + search engine + headless browser (**GUESS** 400-700M) | No nixpkgs module found (Docker-only) | Yes, OIDC supported | TOO HEAVY on a 1.9G node alongside other services | 2 — redundant with Karakeep, no clear edge for this owner |
| [Wallabag](https://github.com/wallabag/wallabag) | PHP/Symfony | Moderate, PHP-FPM stack (**GUESS** 150-250M) | Yes — nixpkgs has no dedicated module confirmed in search; largely deployed via Docker | OIDC is a long-standing open feature request (GitHub #4205, since 2019), not built in | FITS/TIGHT | 2 — mature but OIDC gap is a real friction point given Pocket ID is the whole point |
| [Readeck](https://readeck.org/) | Go, single binary + SQLite | Small, Go-binary profile similar to other single-binary tools (**GUESS** <100M) | No nixpkgs module found | Not confirmed; appears to support only local auth as of 2026 | FITS | 3 — very light but OIDC gap and less mature than Karakeep |

## RSS / feed aggregation

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Miniflux](https://miniflux.app/) | Go, single binary + Postgres | ~10-30 MB idle (Go binary + Postgres) | Yes — `nixos/modules/services/web-apps/miniflux.nix`, `services.miniflux` | Yes — native OAuth2/OIDC support (documented, widely used with Authentik/Pocket ID) | FITS | 5 — tiny footprint, real OIDC, minimal maintenance; textbook fit for this cluster |
| [FreshRSS](https://freshrss.org/) | PHP | PHP-FPM stack adds real overhead vs Miniflux's Go binary (**GUESS** 100+ MB) | Yes — `services.freshrss`, 21 options including `baseUrl`/`database`/`webserver` (nixpkgs issue #346219 notes it currently hard-depends on nginx) | Supports OIDC via extension/proxy auth, less native than Miniflux | FITS | 3 — nice UI but Miniflux already wins on every axis that matters here |
| [RSSHub](https://github.com/DIYgod/RSSHub) (as feed-generation infra, not a reader) | Node/TS | Moderate Node process (**GUESS** 100-200 MB) | No nixpkgs module found (Docker-only) | N/A — internal tool, not user-facing | FITS/TIGHT | 3 — useful to turn non-RSS sites into feeds for Miniflux/Hermes, novel use as automation glue |

## Notes / wiki / personal knowledge management

Owner already runs a git-repo based KB behind Hermes — a git-native, plain-Markdown
tool is a better philosophical fit than a DB-backed wiki that creates a second
source of truth.

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [TriliumNext](https://github.com/TriliumNext/Notes) | Node/Electron-derived server + SQLite | Not precisely quantified in search, but a real memory leak (accumulated listeners) was only just fixed in recent releases, and consistency checks on 20k+ note DBs used to take minutes — indicates non-trivial baseline (**GUESS** 150-300M) | No nixpkgs module confirmed found | Local auth only as of 2026, no native OIDC found | TIGHT | 2 — powerful but a second database-backed KB duplicates Hermes' git KB; skip |
| [SilverBullet](https://silverbullet.md/) | Deno/TS, plain-Markdown-file-backed (no DB) | Single Deno process over a flat Markdown folder — architecturally closest to "git KB with a nice UI" (**GUESS** <100M) | No nixpkgs module found (Docker-only, but trivially packaged since it's a single binary) | Not confirmed native OIDC; likely proxy-auth only | FITS | 4 — markdown-file-native design could literally point at the same git repo Hermes uses, genuinely complementary rather than redundant |
| [Memos](https://github.com/usememos/memos) | Go + SQLite | Small Go binary, single-binary profile (**GUESS** <100M) | No nixpkgs module confirmed | OIDC/OAuth2 supported natively | FITS | 3 — good for quick-capture "tweet to yourself" notes, different niche from a wiki (fast jotting, not structured KB) |
| [Outline](https://github.com/outline/outline) | Node + Postgres + Redis + S3-compatible storage | Multi-service stack (app + Postgres + Redis) — meaningfully heavier than the above (**GUESS** 400-600M combined) | No nixpkgs module found | Yes, strong native OIDC/SAML | TOO HEAVY | 2 — team-wiki grade tool for a single-user homelab, Redis+Postgres+S3 dependency is overkill |

## Document management

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | Python/Django + Postgres + Redis + Tika/OCR workers | Official guidance: ~2 GB RAM minimum, 4 GB recommended; real reports show idle ~600-800 MB with OCR spikes to 1.5-2 GB (GitHub issues #7439, #3616, discussion #9914 — one user saw idle jump from 290 MB to 2.7-4.6 GB just opening the frontend) | No nixpkgs module confirmed in search (Docker-first project) | Yes — native OIDC since v2.5.0+ (via django-allauth openid_connect provider), documented Authentik integration | TOO HEAVY | 2 — genuinely useful for scanned mail/receipts, but its real-world RAM footprint blows every node's cap; would need a dedicated volume+node and still risks OOM during OCR |
| [Docspell](https://docspell.org/) | Scala/JVM | JVM baseline overhead is real even before load (**GUESS** 300-500M idle) | No nixpkgs module found | Supports OIDC | TOO HEAVY | 1 — JVM tax alone rules this out for a 1.9G node |

## Photo management

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Immich](https://github.com/immich-app/immich) | Node/NestJS server + separate ML microservice + Postgres + Redis | Official docs: 6 GB RAM minimum, 8 GB recommended. Real breakdown: server+microservices ~500-800 MB, ML service ~1-2 GB+ during inference; full stack idles 2-3 GB. ML can be disabled to run on ~4 GB, losing face/semantic search | Yes — `search.nixos.org` lists `services.immich` as an available option set | Yes — native OIDC documented at docs.immich.app/administration/oauth | TOO HEAVY | 3 — best-in-class photo app and does have a nixpkgs module, but even with ML off it needs more RAM than one whole node; only viable if dedicated to its own beefier node, which the fleet doesn't have |
| [PhotoPrism](https://www.photoprism.app/) | Go + optional TensorFlow-based ML | Official Plus guidance: 2 cores / 4 GB minimum; in-memory cache doesn't shrink until restart; RPi4 reports ~11% of total system memory at idle (**GUESS** ~200-400M idle without ML) | No nixpkgs module confirmed found | OIDC not confirmed native (proxy-auth common) | TIGHT/TOO HEAVY depending on ML | 2 — lighter than Immich but still cache-hungry and no confirmed native OIDC |
| [LibrePhotos](https://github.com/LibrePhotos/librephotos) | Python/Django + ML | Multi-container stack similar in spirit to Immich (**GUESS** 500M-1G+) | No nixpkgs module found | Not confirmed | TOO HEAVY | 1 — smaller community, same ML weight problem, no upside over Immich |

Verdict for this category: nothing here fits a 1.9 GiB node today. If compute ever
grows (a 5th, bigger node), Immich is the clear pick — it already has a nixpkgs
module and first-class OIDC.

## Media stack complements (Jellyfin/Jellyseerr already deployed)

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Jellystat](https://github.com/CyferShepard/Jellystat) | Node + Postgres | Not quantified in search; Postgres DB grows ~50-200 MB/year for 5 active users, implying a light footprint (**GUESS** 100-200M combined) | No nixpkgs module found (Docker-only) | Not confirmed native OIDC | FITS/TIGHT | 4 — direct Tautulli-for-Jellyfin equivalent, satisfies the "who's watching what" itch cheaply |
| [Streamystats](https://github.com/fredrikburmester/streamystats) | Elixir/Phoenix + Postgres | Newer, less battle-tested than Jellystat, no memory numbers found (**GUESS** similar to Jellystat) | No nixpkgs module found | Not confirmed | FITS/TIGHT | 3 — nicer dashboards per its own docs but Jellystat is more established; only one of the two is worth running |
| [Audiobookshelf](https://github.com/advplyr/audiobookshelf) | Node, single binary | ~150 MB RAM at idle (per search) | Yes — `nixos/modules/services/web-apps/audiobookshelf.nix`, confirmed present through release-26.05, `services.audiobookshelf.enable` | Supports OAuth/OIDC (community-confirmed, generic OIDC provider support shipped) | FITS | 4 — audiobooks/podcasts genuinely complement a video-focused Jellyfin box, has a real nixpkgs module |
| [Navidrome](https://github.com/navidrome/navidrome) | Go, single binary | Under 50 MB RAM even with a 300 GB / ~29,000-song library | Yes — `nixos/modules/services/audio/navidrome.nix`, `services.navidrome.settings`/`.plugins` present since PR #91366 | Subsonic-native auth; OIDC support exists via plugin system (2026 plugin architecture) | FITS | 4 — tiny, real nixpkgs module, fills the "Spotify-but-mine" gap Jellyfin's music support never does well |
| [Komga](https://github.com/gotson/komga) | Kotlin/JVM | No nixpkgs module and no confirmed memory numbers found; JVM baseline should be assumed (**GUESS** 250-400M) | No nixpkgs module found (Docker/JAR only) | Not confirmed | TIGHT | 2 — comics/manga niche is narrow for this owner and JVM tax isn't justified without a stated need |
| [Wizarr](https://github.com/wizarrrr/wizarr) | Python/Flask | No memory numbers found in search, described as "lightweight" (**GUESS** <150M) | No nixpkgs module found (Docker-only) | Not confirmed | FITS (assuming light) | 2 — nice-to-have for onboarding friends to Jellyfin, but low urgency for a single/small-household setup |

## Password / secrets UI, file sync, dashboards, git forge

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Rust, single binary | Real numbers vary a lot by report: ~10-30 MB idle in some homelab reports, another says 15-30 MB rest / 50-80 MB under single-user load / 100-150 MB with 5-10 concurrent users + WebSocket sync; note the build step itself needs ≥7 GB RAM (not a runtime concern, but matters if building on-node rather than via binary cache) | Yes — `services.vaultwarden` with `config`, `dbBackend`, `configurePostgres`, `configureNginx`, `package`, etc. (NixOS wiki + MyNixOS confirm) | SSO plugin exists (bitwarden_rs / vaultwarden SSO via OIDC, community-maintained, works with generic OIDC incl. self-hosted providers) | FITS | 5 — Rust, tiny, real nixpkgs module, real OIDC path, and "own your passwords" is high-value for a DevSecOps engineer who already treats infra as code |
| [Syncthing](https://github.com/syncthing/syncthing) | Go | Idle/settled ~100-180 MB per forum reports; large-file syncs and huge file counts can spike much higher (some reports of runaway growth on pathological workloads) | Yes — mature `services.syncthing` module, long-standing in nixpkgs | N/A — P2P sync tool, no central login/SSO surface to speak of | FITS (idle), watch under heavy sync | 4 — direct value for moving configs/photos/notes between the cluster, Artemis, and phone without a cloud middleman; no OIDC integration is fine since it's not a web login surface |
| [Glance](https://github.com/glanceapp/glance) | Go, single binary | Idles under 25 MB RAM even with dozens of feeds per its own repo's claims; <50 MB reported on a Raspberry Pi 4 | No nixpkgs module confirmed found (Docker/single-binary, trivial to package as a flake derivation) | Not a login-gated app by design (config-file dashboard); can sit behind Pocket ID at the Caddy layer via forward-auth | FITS | 5 — the correct "one glance at everything" status page for this exact fleet, cheapest dashboard by far vs Dashy/Homepage (200 MB+) |
| [Homepage](https://github.com/gethomepage/homepage) | Next.js/Node | Reported 200 MB+ vs Glance's <50 MB, per comparison articles | No nixpkgs module confirmed | Not natively login-gated | FITS/TIGHT | 2 — Glance does the same job for a fraction of the RAM; no reason to run both |
| [Uptime Kuma](https://github.com/louislam/uptime-kuma) | Node + SQLite | ~100 MB per comparison sources | Yes — `services.uptime-kuma` per NixOS wiki/MyNixOS | Whole-app single shared login only, no OIDC gate (per comparison research) | FITS | 3 — nice public status page generator, but Grafana+vmalert+Alertmanager already do synthetic-style alerting; only adds value for a public-facing "is my stuff up" page |
| [Gatus](https://github.com/TwiN/gatus) | Go, single binary, config-as-code | ~30 MB, roughly a third of Uptime Kuma's footprint per direct comparison | Confirmed present in nixpkgs (Go tool, commonly packaged; module existence not 100% verified in this pass — verify before adopting) | Access-gate via basic-auth or OIDC (not a full app login, a config-level gate) — more DevSecOps-native than Kuma's shared login | FITS | 4 — YAML/config-driven like the rest of this owner's stack, smaller than Kuma, and its OIDC gate fits Pocket ID better than Kuma's shared-login model; no fancy public status page though |
| [Forgejo](https://forgejo.org/) (+ Forgejo Actions runner) | Go, single binary + Postgres/SQLite | ~150 MB reported on a low-powered VPS, "happily on 512 MB RAM"; a Codeberg NixOS runner project and a Nix-focused blog post confirm real-world use for exactly this workload | Yes — dedicated NixOS Wiki page for Forgejo, mature `services.forgejo` module | Yes — Forgejo has native OAuth2/OIDC provider support (both as a client and as an OIDC-consuming app) and is commonly wired to Authentik/Pocket-ID-style providers | FITS (server) / TIGHT (with an Actions runner alongside) | 5 — `github.jeiang.dev` is already reserved in Caddy, meaning this was already intended; Forgejo is the obvious, well-trodden, low-RAM Gitea-fork answer, and Forgejo Actions gives CI without adopting a separate heavyweight CI system |
| [Woodpecker CI](https://woodpecker-ci.org/) (alternative CI if not using Forgejo Actions) | Go | Server is lightweight (Go binary); agents run per-job in containers so cost is bursty, not idle | No nixpkgs module confirmed found | Native OAuth via forge (Forgejo/Gitea/GitHub) login | FITS (server) | 3 — solid if Forgejo Actions ever feels limiting, but redundant to stand up both on day one |

## Git forge / CI verdict

Stand up **Forgejo** at `github.jeiang.dev` first — it already has a reserved
hostname, a real nixpkgs module, low measured RAM, and native OIDC. Defer a
dedicated CI runner until there's an actual build to run; Forgejo Actions (using
the existing Forgejo instance) is the lowest-effort next step over standing up
Woodpecker/Drone separately.

## Personal analytics, uptime, feed automation, home automation, novel 2025-2026 picks

| App | Lang | RSS idle / light load | nixpkgs module | OIDC/Pocket ID | Fit | Score |
|---|---|---|---|---|---|---|
| [Umami](https://github.com/umami-software/umami) | Node + Postgres | Lighter than Plausible (no ClickHouse); Node process baseline (**GUESS** 100-200M) | No nixpkgs module confirmed found | Not natively OIDC, but sits behind Pocket-ID-gated Caddy easily since it's low-traffic personal analytics | FITS | 3 — nice for tracking traffic on personal sites (e.g. plyrex.dev), but Plausible/Umami both add a second analytics DB when VictoriaMetrics/Grafana could arguably absorb pageview counters instead |
| [Plausible](https://github.com/plausible/analytics) | Elixir + ClickHouse + Postgres | ClickHouse alone typically wants several hundred MB+ even idle (**GUESS** 500M+ combined) | No nixpkgs module confirmed | Community SSO exists but is a heavier lift | TOO HEAVY | 1 — ClickHouse dependency alone rules this out |
| [Beszel](https://github.com/henrygd/beszel) | Go (agent+hub), SQLite | Agent uses ~10-23 MB RAM per 2026 benchmarks (vs Netdata 200-500 MB, Datadog 500 MB+) | Yes — `nixos/modules/services/monitoring/beszel-agent.nix` confirmed present in release-26.05 | Hub has its own lightweight auth; not confirmed OIDC-native | FITS | 3 — genuinely tiny, but overlaps heavily with the existing VictoriaMetrics+Grafana stack; only useful as a quick per-node systemd-free glance, not a replacement |
| [Gatus / Uptime Kuma] | — | (see above table) | — | — | FITS | (duplicated above) |
| [changedetection.io](https://github.com/dgtlmoon/changedetection.io) | Python/Flask | ~100 MB RAM base (barely, <1% CPU); adding a Playwright container for JS-heavy pages roughly doubles memory and has a known nixpkgs-documented leak | Yes — nixpkgs package/module present (confirmed via nixpkgs source at multiple release branches including 26.05) | Not confirmed native OIDC (basic-auth typical) | FITS (basic mode) / TIGHT (with browser rendering) | 4 — genuinely useful and novel-feeling: watch vendor pricing pages, docs, job postings, or NixOS release notes for changes and get pinged via existing Alertmanager/Hermes; keep browser-rendering off given the memory leak note |
| [n8n](https://n8n.io/) | Node/TypeScript | Reports vary widely: some idle at ~860 MB with 0% CPU, "queue mode" roughly doubles idle RAM; a single webhook workflow handling a large JSON payload can spike 150-800 MB | Yes — `nixos/modules/services/misc/n8n.nix`, `services.n8n.enable/environment/openFirewall/package` | Not confirmed native OIDC (typically behind proxy-auth) | TOO HEAVY | 2 — the automation itch is real for this owner, but n8n's documented idle RAM alone can exceed a whole node's budget; Huginn/Node-RED are lighter alternatives worth a follow-up look if this itch persists |
| [Node-RED](https://nodered.org/) | Node | Lighter than n8n by design (flow-based, no heavy queue-mode option) (**GUESS** 100-200M idle) | Not confirmed in nixpkgs search this pass | Not confirmed native OIDC | FITS/TIGHT | 3 — better fit than n8n if the goal is small glue automations (e.g. wiring changedetection.io -> Hermes/Telegram) rather than a full workflow platform |
| Home Assistant | Python | Official guidance: 2 GB min / 4 GB recommended even for a modest device count; a realistic 20-device setup already runs 2-4 GB | No realistic fit regardless of module (module exists in nixpkgs, `services.home-assistant`, well known) | Yes, HA supports OIDC via community integrations | TOO HEAVY, and wrong shape | 1 — beyond the RAM problem, HA's entire value proposition (Zigbee/Z-Wave/local device discovery) needs a box on the local LAN, not a Hetzner cloud VM; this is a hard "don't," not just a tight fit |
| [Open WebUI](https://github.com/open-webui/open-webui) | Python (FastAPI) + Svelte | Users report 500 MB - 1+ GB idle RAM even with no active session, vs the ~20 MB a comparable lightweight service would use; known memory-leak reports tied to embedding models | No nixpkgs module confirmed found | Not confirmed native OIDC (proxy-auth typical) | TOO HEAVY | 2 — tempting since Artemis already runs llama.cpp/llama-swap, but Open WebUI's own idle footprint alone busts a node's cap; llama-swap's built-in web UI or a much lighter chat client is a better fit if a UI is wanted at all |
| [LiteLLM proxy](https://github.com/BerriAI/litellm) (as an OpenAI-compatible gateway in front of Artemis's llama-swap) | Python | Not deeply researched this pass; FastAPI-based proxy, expect a modest baseline (**GUESS** 150-300M) | No nixpkgs module confirmed found | Supports OIDC/JWT auth for its own admin UI | TIGHT | 3 — genuinely novel idea for this specific owner (unify API-key access to Artemis's local models from any cluster service or Hermes), worth a deeper look before committing given the GUESS-heavy numbers here |

## Ranked shortlist

### Top 10 worth doing (in build order)

1. **Forgejo** (+ Forgejo Actions later) — hostname already reserved, real nixpkgs module, ~150 MB measured, native OIDC. Do this first; everything else is optional polish.
2. **Miniflux** — 10-30 MB RAM, real nixpkgs module, native OIDC. Essentially free to run.
3. **Glance** — <25-50 MB, single binary, gives a real payoff (one page for the whole fleet) for almost no cost. Pair it with Caddy forward-auth to Pocket ID since it has no login of its own.
4. **Vaultwarden** — tiny Rust binary, real nixpkgs module, community OIDC plugin, and a password manager is overdue infrastructure for someone already running SSO and a Nix binary cache.
5. **Gatus** — ~30 MB, config-as-code (fits the "everything declarative" ethos better than Uptime Kuma's DB-backed UI), OIDC-capable access gate.
6. **Navidrome** — <50 MB even at a real-world library size, real nixpkgs module, fills a genuine Jellyfin gap (music).
7. **Audiobookshelf** — ~150 MB, real nixpkgs module, OIDC support, direct complement to the existing Jellyfin/Jellyseerr stack.
8. **Karakeep** — heavier (200-800 MB with search+crawler) but the strongest all-in-one read-it-later tool with native OIDC; put it on whichever node has the most headroom.
9. **Syncthing** — 100-180 MB idle, mature nixpkgs module, solves a real cross-device sync need (configs/notes/photos) without a cloud dependency.
10. **changedetection.io** — ~100 MB in basic mode, real nixpkgs module; genuinely novel use here is wiring it to Hermes/Alertmanager for "notify me when X page changes" instead of polling manually.

### Worth trying if compute grows (5th/bigger node, or after trimming something else)

- **Immich** — best-in-class photo app with a real nixpkgs module and native OIDC, but the ML pipeline alone needs 1-2 GB; wait for a bigger box rather than crippling it by disabling ML.
- **Jellystat** — cheap Tautulli-for-Jellyfin equivalent once there's spare room next to the media stack (not on these 4 nodes since Jellyfin itself lives elsewhere).
- **SilverBullet** — markdown-file-native notes tool that could plausibly point at the same git repo Hermes' KB uses; worth a prototype once there's time to validate the git-file overlap doesn't fight Hermes' own writes.
- **LiteLLM proxy** — unify access to Artemis's llama-swap models behind one gateway; numbers here are GUESS-heavy, so benchmark actual RSS before committing a node's budget to it.
- **Node-RED** — lighter automation glue than n8n for small jobs like changedetection.io -> Telegram, if the itch for "if this then that" grows beyond what a cron/systemd timer + Hermes can express.

### Skip and why

- **Paperless-ngx** — real-world idle RAM (~600-800 MB, spiking to 1.5-4+ GB during OCR/frontend use per multiple GitHub issues) makes it a reliable way to OOM a 1.9 GiB node; needs a dedicated bigger box to be safe.
- **PhotoPrism / LibrePhotos** — same ML-weight problem as Immich without Immich's larger community or as-clean a nixpkgs story.
- **Docspell** — JVM baseline tax isn't worth it when Paperless-ngx (already too heavy) is the more capable alternative anyway.
- **Outline / Trilium** — both duplicate the git-repo KB Hermes already owns, adding a second source of truth (and, for Outline, a Postgres+Redis+S3 stack) for no compounding benefit.
- **Home Assistant** — wrong shape, not just too heavy: it wants to be a local-LAN hub talking to Zigbee/Z-Wave radios, not a cloud VM with no attached hardware. Don't force it onto Hetzner.
- **n8n / Open WebUI / Plausible** — each has a documented idle RAM footprint (860 MB, 500 MB-1+ GB, ClickHouse-backed respectively) that alone exceeds a whole node's budget; none of them are close calls.
- **Homepage / Dashy** (vs Glance) — functionally redundant with Glance at 4-8x the RAM cost for the same "status page" job; no reason to run two dashboards.
- **Uptime Kuma** (vs Gatus) — heavier, DB-backed, and its access model is a single shared app login rather than an OIDC gate; keep it only if the public branded status-page feature is specifically wanted, otherwise Gatus wins.
- **Komga / Wizarr** — narrow-value niches (manga library, invite UX) for this specific owner; revisit only if a stated need shows up, not preemptively.

## Notes on verification gaps

Several apps could not be confirmed to have a nixpkgs module in this pass despite
being popular (Karakeep, Linkwarden, Wallabag, Readeck, PhotoPrism, LibrePhotos,
Docspell, Komga, Wizarr, Jellystat, Streamystats, Umami, Plausible, Open WebUI,
LiteLLM, RSSHub, TriliumNext, Memos, Outline, SilverBullet, Node-RED, Woodpecker).
Absence of a hit in this pass is not proof of absence — verify directly against
`search.nixos.org` before writing the actual NixOS module for any of these, since
nixpkgs adds new service modules continuously. Several memory figures are marked
GUESS where no report gave a concrete number; benchmark on an actual node before
setting `MemoryMax` for any of these rather than trusting the estimates here.
