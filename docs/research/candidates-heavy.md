# Heavy-app re-evaluation on merit (2026-08-22)

Scope: re-assess apps the earlier pass (`docs/research/candidates-apps.md`) ruled
out purely on the 1.9 GiB/node `MemoryMax` budget. Owner has said: judge each on
what it delivers, and separately state real cost. He'll consider a new, larger
node if something is worth it, and wants cheaper alternatives named.

Nixpkgs module claims below are verified against pinned revision
`2fcb964de67fcf60b43471c55d5d99e61a9ccb5a` via `module-list.nix` + reading each
module's option block, not assumed. This corrects several "no module found"
calls from the earlier pass — nixpkgs has since gained first-party modules for
Immich, Paperless, Outline, TriliumNext, Karakeep, and Windmill.

**Hetzner pricing note**: Hetzner raised CPX/CCX prices 2.1x-2.75x on 2026-06-15
(CX/CAX rose only ~1.3x). Post-hike EUR/month, Germany/Finland region: CX23
(2vCPU/4GB) €5.49, CX33 (4/8) €8.49, CX43 (8/16) €15.99; CAX11 (2/4 ARM)
€5.99, CAX21 (4/8) €10.49, CAX31 (8/16) €20.99; CPX22 (2/4) €19.49, CPX32 (4/8)
€35.49, CPX42 (8/16) €69.49; CCX13 (2/8 dedicated) €42.99, CCX23 (4/16)
€85.99, CCX33 (8/32) €138.49. **CAX (ARM, shared) is now the clearly cheapest
path to real RAM** — CAX31 gives 16 GB for €20.99/mo, less than half a CPX42
with the same RAM. Only reach for CPX/CCX if ARM compatibility is a blocker
(it isn't, for anything below) or dedicated vCPU is required.

---

## Immich (photo management)

**Merit**: Best-in-class self-hosted photo app in 2026 — nothing else combines
mobile auto-backup, ML search/faces, shared albums, and this pace of
development. No credible successor has emerged; it's still the default
recommendation across r/selfhosted-adjacent comparisons.

**Real cost**: Official docs list 6 GB RAM minimum / 8 GB recommended, 2-4
vCPU. Idle with ML enabled realistically runs 2-3 GB combined
([SSD Nodes](https://www.ssdnodes.com/learn/immich-ram-and-storage-requirements),
[docs.immich.app](https://docs.immich.app/install/requirements/)). ML
(face recognition, CLIP smart search) is the entire cost driver — it can be
disabled per-feature or the `immich-machine-learning` container removed
entirely, dropping the app+Postgres+Redis core to roughly 500 MB-1 GB, but
that gives up the two features that make Immich worth choosing over a plain
file server. A CAX21 (4 vCPU/8 GB, €10.49/mo) fits the full stack with ML;
CAX31 (8/16 GB, €20.99/mo) gives real headroom for a growing library plus
transcoding jobs.

**Nixpkgs module**: Real service module — `services.immich` at
`nixos/modules/services/web-apps/immich.nix`, with dedicated
`machine-learning.enable`, `postgresql` auto-provisioning, and
`settings.oauth.*` options.

**OIDC**: Confirmed native — `services.immich.settings.oauth.*` maps directly
to Immich's built-in OAuth/OIDC admin settings
([docs.immich.app/administration/oauth](https://docs.immich.app/administration/oauth)).
Works with Pocket ID as a standard OIDC provider.

**Lighter alternative**: None that matches the feature set. PhotoPrism is
lighter (2-4 GB recommended per its Plus docs, no confirmed native OIDC) but
its ML/cache story is arguably worse per-MB than Immich's, and it has no
nixpkgs module. Not a real downgrade path — if photo management is wanted,
it's Immich or nothing serious.

**Score: 5/5 — worth a new node.** Best-in-class, real module, real OIDC,
and the cost driver (ML) is the actual point of running it, not incidental
bloat.

---

## Paperless-ngx (document management/OCR)

**Merit**: Still the clear leader for self-hosted scan-and-search document
management in 2026 — OCR, tagging, full-text search, 24k+ GitHub stars,
active maintenance. Papra is the one credible newer/lighter alternative
worth naming, but it's materially less mature and less capable
(no comparable OCR/consumption pipeline maturity).

**Real cost**: Official guidance is ~2 GB RAM minimum, 4 GB recommended.
Real-world GitHub issues report idle around 600-800 MB with OCR spikes to
1.5-2 GB, and one report of idle jumping from 290 MB to 2.7-4.6 GB simply
from opening the frontend (GitHub #7439, #3616, discussion #9914). This is a
genuine multi-service stack: Django app + Postgres + Redis + Tika/OCR
workers. A CAX21 (4/8 GB, €10.49/mo) covers the documented minimum with
margin; CAX31 (8/16 GB, €20.99/mo) is the safer choice if OCR runs on
scanned mail/receipts regularly rather than as a rare batch job.

**Nixpkgs module**: Real service module now exists —
`services.paperless` at `nixos/modules/services/misc/paperless.nix` (the
earlier pass's "Docker-first project, no module" call is now out of date).

**OIDC**: Native since Paperless-ngx v2.5.0+ via django-allauth's
`openid_connect` provider, documented with Authentik-style setups; works
the same way with Pocket ID as a generic OIDC provider.

**Lighter alternative**: Papra (Node/TS, positioned as "the lightest
Paperless-ngx alternative") is worth a follow-up look if OCR quality proves
adequate, but it has no nixpkgs module and a much smaller track record —
don't switch to it sight-unseen.

**Score: 4/5 — worth provisioning for, second priority after Immich.**
Genuinely useful (scanned mail, receipts, warranty docs), has a real module
and real OIDC now; only loses a point versus Immich because the OCR spike
behavior needs headroom, not just a bigger idle baseline.

---

## Karakeep (bookmarking w/ AI tagging)

**Merit**: Still the strongest all-in-one read-it-later/bookmark tool with
AI auto-tagging in 2026 — this was already the earlier pass's top pick in
its category and nothing has displaced it.

**Real cost**: Core app ~200 MB, Meilisearch ~100 MB, headless Chromium
crawler spikes to ~500 MB during archiving — "comfortable on a 2 GB VPS"
per multiple 2026 write-ups
([berkem.xyz](https://berkem.xyz/blog/self-hosted-bookmarking-with-raspberry-pi-karakeep/)).
Two real caveats found this pass: a reported memory leak growing RAM over
time (GitHub #2344, with Pangolin specifically) and a known issue importing
large batches (~1,500 links) exhausting memory (GitHub #1748). This is
lighter than the other apps here — it doesn't need a dedicated new node, a
CX33/CAX21-class box (8 GB) with generous headroom handles it comfortably,
and it could plausibly share space with something else rather than justify
its own node.

**Nixpkgs module**: Real service module now exists — `services.karakeep`
at `nixos/modules/services/web-apps/karakeep.nix` (earlier pass's "Docker
only" call is now out of date).

**OIDC**: Confirmed native, generic OIDC via `OAUTH_WELLKNOWN_URL` /
`OAUTH_CLIENT_ID` / `OAUTH_CLIENT_SECRET` env vars, with a Pocket ID-specific
example page at [pocket-id.org/docs/client-examples/karakeep](https://pocket-id.org/docs/client-examples/karakeep).

**Lighter alternative**: Linkding remains the lightest pure-bookmarking
option (no AI tagging, no crawler) if the AI tagging isn't actually used
day-to-day.

**Score: 3/5 — nice-to-have, not a node driver.** It's real and it's got a
module and OIDC now, but it doesn't need dedicated hardware; run it wherever
there's 500 MB-1 GB spare, restart-on-schedule to work around the leak
report, and skip bulk imports.

---

## Outline and TriliumNext (notes/wiki)

**Merit unchanged from the earlier pass's core argument**: the owner already
runs a git-repo KB behind Hermes. A DB-backed wiki (Outline: Postgres+Redis+
S3) or even a SQLite-backed one (Trilium) is a second source of truth for
the same job, not a complementary tool. This is a philosophy call, not a
resource call — worth restating even though the prompt asked to ignore
resource constraints, because it's the stronger reason to skip both.

**Real cost, on merit**:
- **Outline**: Node app + Postgres + Redis + S3-compatible storage,
  meaningfully heavier than any single-binary tool here (earlier pass's
  400-600 MB combined GUESS stands; no new concrete number found).
  CAX21 (4/8 GB, €10.49/mo) would run it comfortably.
- **TriliumNext**: Genuinely light — ~100 MB idle, 150-300 MB typical, up to
  200-500 MB with a large database, single container + SQLite. Runs fine on
  a Raspberry Pi per multiple 2026 write-ups. This does **not** need a new
  node at all.

**Nixpkgs modules**: Both now have real service modules — `services.outline`
(`nixos/modules/services/web-apps/outline.nix`) and `services.trilium-server`
(`nixos/modules/services/web-apps/trilium.nix`), correcting the earlier
pass's "no module found" call on both.

**OIDC**: Outline has strong native OIDC/SAML (unchanged from earlier pass —
still true and still the module supports `oidcAuthentication` options
directly, including a documented Dex/generic-OIDC recipe on the NixOS
wiki). **TriliumNext has gained native OIDC since the earlier pass** — it
now supports an external OIDC issuer via `TRILIUM_OAUTH_*` env vars/settings,
confirmed working with Authentik/Authelia/Pocket ID in 2025-2026 GitHub
discussions, though one open limitation stands out: Trilium currently
implements OIDC *authentication* only, not *authorization* — anyone who can
log into the IdP can log into Trilium, there's no per-user gating inside the
app itself (open feature request as of 2026-02-03). For a single-operator
homelab that's a non-issue.

**Lighter alternative**: SilverBullet (Markdown-file-backed, no DB) remains
the most philosophically consistent pick if a wiki is ever wanted — it could
point at the same git repo Hermes' KB uses instead of creating a second
database.

**Score: Outline 2/5, TriliumNext 2/5 — skip both, on merit, not weight.**
TriliumNext is cheap enough now to run on a shared node without denting a
budget, and it even has OIDC now — but running it still means a second
Markdown-adjacent knowledge store next to Hermes' git KB, duplicating
retrieval/search paths for no compounding benefit. Outline adds a
Postgres+Redis+S3 dependency on top of the same duplication problem for a
team-wiki feature set nobody but a single user needs. If the itch is real,
prototype SilverBullet against the existing git KB before reaching for
either of these.

---

## n8n (automation)

**Merit**: Still the most capable/integration-rich (400+ nodes) self-hosted
automation platform in 2026, and the community itch for it is real given
the owner already has changedetection.io-style signals worth wiring up.

**SSO status — confirmed still paid-tier only in 2026.** n8n Cloud's free
tier was discontinued in late 2025; self-hosted Community Edition is free
and full-featured for workflows, but OIDC/SSO specifically requires a
Startup license starting at $400/mo (billed annually) or the Cloud Business
tier at €800/mo
([truehost.com](https://truehost.com/n8n-free-2026-prices/),
[docs.n8n.io/deploy/host-n8n/configure-n8n/security/configure-sso](https://docs.n8n.io/deploy/host-n8n/configure-n8n/security/configure-sso)).
This is a hard blocker for the owner's "everything behind Pocket ID" model
at any node size — money doesn't fix it, only a license does. One
community workaround exists: `n8n-oidc`, a drop-in OIDC auth patch released
December 2025 by a third-party developer
([cweagans.net/2025/12/announcing-n8n-oidc](https://www.cweagans.net/2025/12/announcing-n8n-oidc/)) —
unofficial, unaudited, applies to the container directly; treat as a
maybe-later experiment, not something to build a Nix module around today.

**Real cost**: Reports vary widely — idle around ~860 MB RAM at 0% CPU is a
commonly cited real number, "queue mode" roughly doubles that, and a single
large-payload webhook workflow can spike 150-800 MB on top. A CAX21 (4/8 GB,
€10.49/mo) covers idle with margin; CAX31 (8/16 GB) if queue mode or heavy
payloads are expected.

**Nixpkgs module**: Real module, `services.n8n` at
`nixos/modules/services/misc/n8n.nix` (unchanged from earlier pass).

**Alternatives checked as requested — Windmill and Activepieces**:
- **Windmill**: code-first (12 languages), AGPLv3, has a real nixpkgs
  module (`services.windmill`). **Same problem as n8n**: SSO/OIDC is
  explicitly Enterprise-only — the Community Edition excludes SSO, audit
  logging, and worker groups, confirmed current as of March 2026.
- **Activepieces**: MIT-licensed core, easiest UX of the three, 200+
  integrations. **Same problem again**: SSO, RBAC, audit logs, and Git Sync
  are gated behind a paid/Enterprise plan; Community Edition is free but
  auth-integration-free. No nixpkgs module found for Activepieces at the
  pinned revision (only n8n and Windmill exist as modules).

None of the three self-hosted automation platforms ships free OIDC/SSO in
2026 — this is an industry-wide monetization pattern for this category, not
an n8n-specific gap. If OIDC is a hard requirement, all three fail it
equally; the deciding factor becomes integration count and code-flexibility
instead. On that axis n8n wins for this owner (best integration coverage,
most mature nixpkgs module, and the changedetection.io/Hermes glue use case
fits n8n's node-based UI better than Windmill's code-first model).

**Score: 2/5.** Genuinely useful automation, real module, real RAM cost is
survivable on a mid CAX box — but paying $400/mo (more than 30+ CAX31
instances) for SSO, or running it un-integrated with Pocket ID (a real
auth-model regression for this owner), or gambling on an unofficial
third-party OIDC patch, are the only three options. Not worth a dedicated
node purchase on SSO grounds alone; revisit only if the un-audited
`n8n-oidc` patch gains real adoption/security review, or if local-auth (no
SSO) is acceptable for this one app.

---

## Open WebUI (LLM chat UI)

**Merit**: Still the most feature-complete self-hosted ChatGPT-style UI
(RAG, multi-model routing, tool calling), but Artemis already runs
llama.cpp/llama-swap, and llama.cpp shipped its own native SvelteKit-based
WebUI in 2026 (`llama-server`'s built-in UI, see
[ggml-org/llama.cpp discussion #16938](https://github.com/ggml-org/llama.cpp/discussions/16938)) —
a genuinely better-fit "something better has emerged" answer for this
specific owner, since it needs zero extra services and talks directly to
the backend already running.

**Real cost**: Users report 500 MB-1+ GB idle RAM with no active session,
versus ~20 MB for a comparable lightweight service, plus known memory-leak
reports tied to embedding models. This is a Python/FastAPI + Svelte stack
that carries real baseline weight independent of any model it's talking to.
A CAX21 (4/8 GB, €10.49/mo) would run it, but that's paying cloud RAM to
host a *UI* for inference that already happens on Artemis's home GPU box —
architecturally backwards.

**Nixpkgs module**: Real module, `services.open-webui` at
`nixos/modules/services/misc/open-webui.nix`.

**OIDC**: Not confirmed native in this pass; proxy-auth (trusted header)
is the typical deployment pattern reported.

**Lighter alternative — the actual recommendation**: run Open WebUI (or
skip it) directly on Artemis rather than provisioning cloud RAM for it, or
use llama.cpp's own bundled WebUI for zero additional processes. If a
richer chat UI is wanted from anywhere on the mesh, LibreChat and Jan.ai
were named as 2026-era lighter/more-maintained alternatives in comparison
write-ups, though neither was independently RAM-benchmarked this pass.

**Score: 1/5 — not worth a Hetzner node at any size.** The compute this app
wants to talk to already lives on a home GPU box on the same NetBird mesh;
paying for cloud RAM to run a UI that proxies to home hardware inverts the
architecture for no benefit. If a chat UI is wanted, put it on Artemis
itself or use llama.cpp's native WebUI.

---

## Home Assistant

**Merit**: Still the best home-automation hub, unchanged assessment.

**Real cost**: Official guidance: 2 GB RAM minimum, 4 GB recommended; a
realistic 20-device setup already runs 2-4 GB. Not extreme by today's
Hetzner CAX pricing (CAX21 at 4/8 GB, €10.49/mo, would technically fit) —
but that's the wrong question.

**The actual blocker, restated as requested**: HA's core value (Zigbee/
Z-Wave radio pairing, local mDNS/SSDP device discovery, Matter, Bluetooth
proxies) requires physical LAN presence. None of the four Hetzner nodes has
any LAN-adjacent hardware — they're cloud VMs with no radios, no local
broadcast domain, nothing to discover. **Home Assistant belongs on the home
desktop (Artemis) or a small dedicated LAN device, not Hetzner, regardless
of node size.** This is architecture, not a resource problem — provisioning
a bigger cloud node doesn't fix "no Zigbee dongle, no LAN."

**Nixpkgs module**: Real module, `services.home-assistant` at
`nixos/modules/services/home-automation/home-assistant.nix`, well
established.

**OIDC**: Yes — `hass-oidc-auth` (HACS custom integration) supports Pocket
ID specifically, with a documented provider-configuration page
([github.com/christiaangoossens/hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth/blob/main/docs/provider-configurations/pocket-id.md)),
actively maintained through 2026. This part checks out fine wherever HA
ends up running.

**Score: 1/5 for Hetzner at any size — but recommend running it on Artemis
instead**, where it has LAN presence, real headroom, and can still use the
same Pocket ID OIDC integration. Not a "skip entirely" verdict — a
"wrong host" verdict.

---

## Frigate NVR

**Note as given**: the fleet's camera-ingest module
(`modules/nixos/camera-ingest/default.nix`) already receives phone-camera
uploads over a dedicated WireGuard tunnel (`wg-camera`, UDP 51822) into an
nginx WebDAV spool on legion-node1, then relays them onward to Pixeldrain
via `rclone`. This is a **store-and-forward upload receiver for a phone's
own WireGuard client**, not a live RTSP/camera-stream pipeline — there is
no continuous video feed, no camera decoding, and nothing resembling
Frigate's actual job in this architecture today.

**Merit**: Frigate is genuinely best-in-class for real-time NVR + AI object
detection when there *are* RTSP-capable IP cameras to watch continuously.
That is not what this fleet has. The existing camera-ingest setup is
solving a different, simpler problem (get photos/clips off a phone SD card
onto cloud storage), and Frigate would not replace or improve it — Frigate
has no concept of "phone pushes files periodically over WireGuard," it
expects a persistent camera stream to analyze frame-by-frame.

**Real cost, if it were relevant**: 4 GB RAM is the bare minimum for a
handful of cameras with a hardware accelerator; 16 GB is Frigate's own
"highly recommended" tier for 8 cameras with mixed activity, and it
specifically wants AVX/AVX2 CPU support plus either an iGPU (OpenVINO,
Coral is now deprecated for new installs) or a Hailo HAT for real-time
detection. This is fundamentally a box that needs a GPU/NPU and sustained
CPU headroom, not something a general-purpose cloud VM does well or cheaply
even at CCX-dedicated-vCPU tiers.

**Nixpkgs module**: Real module, `services.frigate` at
`nixos/modules/services/video/frigate.nix`.

**OIDC**: Not applicable/not the relevant integration point — Frigate is
typically placed behind a reverse-proxy auth gate (Caddy forward-auth to
Pocket ID) rather than having native OIDC login, same pattern as Grafana or
any other app without built-in OIDC.

**Score: 1/5 — not applicable, not just "too heavy."** There's no actual
camera-stream workload for Frigate to serve here; the current camera-ingest
module already does the real job (durable phone-upload relay) at ~256 MB
combined `MemoryMax`. If the owner ever adds real IP cameras with
continuous RTSP feeds, Frigate becomes worth re-evaluating then — and it
would want a GPU-having box (Artemis, or a dedicated NVR appliance), not a
Hetzner VM, regardless of instance size.

---

## Ranked verdict

**Justifies a new node: Immich (5/5) and Paperless-ngx (4/5), together.**
Both are genuinely best-in-class, both now have real first-party nixpkgs
modules and confirmed native OIDC (correcting the earlier pass's "no
module" calls on both), and both have a legitimate, non-negotiable RAM
floor that no lighter alternative actually replaces without losing the
features that make them worth running. A single **CAX31 (8 vCPU/16 GB ARM,
€20.99/mo)** comfortably runs Immich-with-ML plus Paperless-ngx side by
side with real headroom for OCR/inference spikes — cheaper than a single
CPX42 (8/16 GB, €69.49/mo) at the same spec, since ARM is unaffected by the
June 2026 CPX/CCX price shock. Confirm ARM64 builds exist for both before
committing (both are widely reported running on ARM/Raspberry Pi-class
hardware in 2026 write-ups, so this should not be a blocker).

**Better served by a lighter alternative or a different host, not a new
node:**
- **TriliumNext** — cheap enough (100-300 MB) to slot onto an existing
  node's headroom if wanted despite the KB-duplication concern; no new
  hardware needed either way.
- **Karakeep** — real and improved (module + OIDC now confirmed), but its
  500 MB-1 GB footprint fits existing headroom once trimmed elsewhere; not
  a node driver on its own.
- **Home Assistant** — not a sizing problem, a placement problem: put it on
  Artemis (LAN presence, spare RAM, same Pocket ID OIDC integration works
  there too).
- **Open WebUI** — same logic: it wants to sit next to the inference engine
  it talks to, which is Artemis, not a cloud VM with no GPU.
- **n8n** (and Windmill/Activepieces, checked as requested) — all three
  gate OIDC/SSO behind paid tiers in 2026; this is a licensing wall, not a
  resource one, so no node size fixes it. If local-auth-only is acceptable
  for just this one app, n8n on a CAX21 is fine; otherwise wait for the
  unofficial `n8n-oidc` patch to mature.

**Still not worth it at any size:**
- **Outline** — duplicates the Hermes git-repo KB with a heavier
  Postgres+Redis+S3 stack for no compounding benefit; SilverBullet is the
  better prototype target if a wiki UI is genuinely wanted.
- **Frigate** — there is no camera-stream workload for it to serve; the
  existing `camera-ingest` module already solves the actual problem
  (durable phone-upload relay) for a fraction of the resources, and
  Frigate's real requirement (GPU/NPU + continuous RTSP) doesn't map to a
  general-purpose Hetzner VM regardless of size.
