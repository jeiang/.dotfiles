# Research index

Survey of self-hosted tooling, infrastructure alternatives, and flake
architecture, run 2026-08-22. This file is the entry point: it records what
was decided and why. The per-topic documents hold the evidence.

## How this was researched

Sonnet subagents ran the surveys (web search, upstream documentation, the
GitHub API for maintenance and activity checks, community reports for
real-world memory figures). Load-bearing claims were re-verified directly,
because the agents checked nixpkgs `master` while this flake pins a specific
revision.

Every "module confirmed" below was checked against `2fcb964`, the pinned
nixpkgs revision at the time of the survey, via `nixos/modules/module-list.nix`.
Also verified directly: that the NVD feeds vulnix depends on still resolve,
that the flake evaluates after each edit, and deploy-rs's rebuild cost under
a `follows`.

**Memory figures throughout are third-party reports, not measurements.**
Several are marked GUESS in the source documents. Benchmark on a node before
setting any `MemoryMax`.

## Documents

| Document | Scope |
| -------- | ----- |
| [candidates-apps.md](candidates-apps.md) | Applications for the Legion fleet |
| [candidates-heavy.md](candidates-heavy.md) | Heavy applications re-evaluated without the per-node RAM ceiling |
| [candidates-artemis.md](candidates-artemis.md) | Desktop and GPU workloads |
| [infra-alternatives.md](infra-alternatives.md) | Audit of the current infrastructure against 2026 alternatives |
| [flake-paradigms.md](flake-paradigms.md) | Flake architecture, deployment, secrets, testing |
| [paper-2608.16157.md](paper-2608.16157.md) | arXiv:2608.16157, FreeToken MoE serving |

Catalog surveys, each screened for prompt injection before use and each
verified against the pinned nixpkgs revision:

| Document | Catalog surveyed |
| -------- | ---------------- |
| [catalog-selfhosted.md](catalog-selfhosted.md) | awesome-selfhosted.net |
| [catalog-sysadmin.md](catalog-sysadmin.md) | awesome-sysadmin, awesome-status-pages |
| [catalog-macos.md](catalog-macos.md) | open-source-mac-os-apps, judged against ADR 0009 |
| [catalog-network-storage.md](catalog-network-storage.md) | awesome-network-automation, awesome-storage |

### Catalog findings

The four catalogs produced far less than their size suggests, which is
itself the finding: most entries duplicate something already running or
assume an environment this fleet does not have.

Worth acting on:

- **reaction** — Rust log-pattern daemon, real NixOS module. Fills the
  log-based alerting gap named below. The strongest single result of the
  catalog sweep.
- **Warpgate** — Rust SSH/HTTPS/database bastion, OIDC-native, real module.
  Closes a genuine session-audit gap.
- **Anubis** — Go anti-scraper gate, real module. Complements CrowdSec
  rather than duplicating it.
- **Healthchecks** — dead-man's-switch monitoring, real module. Partial
  cover for backup verification.
- **SearXNG** — real module; private search backend for Hermes.
- **GoAccess** — package-only CLI, zero runtime cost, useful for Caddy log
  triage.

macOS picks for Zakkart, all plain nixpkgs and needing no ADR-0009
exception: Rectangle, zoxide, Karabiner-Elements, MonitorControl,
Beekeeper Studio, LuLu, AltTab, Stats. Note that CopyQ, MQTTX and
Cryptomator are Linux-only in the pinned nixpkgs despite being
cross-platform upstream, so each would need a declared cask exception;
Hammerspoon has no darwin package at all.

Explicit negatives, recorded so they are not re-surveyed:

- **Network automation does not apply.** Ansible, NAPALM, Nornir, RANCID,
  Oxidized, Batfish, SuzieQ and NetBox all exist to manage mutable,
  CLI-driven network devices. This fleet has none: `_service-inventory.nix`
  is already a compile-time-checked source of truth that deploy-rs applies
  directly. NetBox was considered specifically and rejected — a
  Postgres-and-Redis application to track four IP addresses currently held
  in twelve lines of Nix.
- **awesome-storage yielded nothing to adopt.** restic already covers
  backup, deduplication and encryption; distributed filesystems do not fit
  1.9 GiB nodes. Garage is the one TRY, with the caveat that hosting it on
  the same four nodes as a restic target defeats off-fleet durability.
- **Gatus is reconfirmed** as the status-page pick — the only option across
  either catalog with a real NixOS module, against eight alternatives.
- Neither catalog offers anything for CVE scanning, S3 object-lock, or
  secret rotation. awesome-sysadmin has no security category at all.

## Implemented

- Removed the `jellyfin.plyrex.dev` / `seerr.plyrex.dev` placeholder routes.
  The domain is no longer maintained and Jellyfin is not being deployed, so
  the 503 placeholders had no future backend to migrate to.
- `deploy-rs` now follows nixpkgs. It was the only input carrying its own,
  pinned at 2025-03-26, so every evaluation fetched a second
  seventeen-month-old tree. deploy-rs builds from source against the shared
  nixpkgs; garret absorbs that after the first build.
- Weekly vulnix scan of each host's runtime closure against the NVD feeds,
  one matrix leg per host. Deliberately a workflow rather than a flake check:
  vulnix fetches NVD at run time, and a sandboxed derivation has no network,
  so a check would need `--impure`, which CI does not get. Non-blocking by
  design — a nixpkgs closure always carries known unpatched CVEs, and a
  permanently red job is a job everyone learns to skip.

## Build verification, 2026-08-22

Five implementation worktrees were built on artemis (`artemis.jeiang.vpn`,
x86_64-linux, 8 cores / 93 GiB) via `--eval-store auto --store ssh-ng://`.
This machine is aarch64-darwin with no local Linux builder, so agent claims
of a passing build are not self-verifiable and were re-run here.

| Worktree | Host | Result |
| -------- | ---- | ------ |
| Anubis | legion-node1 | passes |
| Glance + Gatus | legion-node2 | passes |
| Miniflux + changedetection.io | legion-node1 | fails, sops manifest |
| Qdrant + whisper.cpp | artemis | fails, qdrant does not compile |
| Warpgate | -- | not implemented, rejected on reasoning |

### qdrant does not build at this nixpkgs pin

`qdrant-1.18.2` fails to compile against nixpkgs `2fcb964`, and it is not
the fault of any configuration in this repo -- building the stock
`nixpkgs.qdrant` derivation reproduces it exactly:

```
error: intrinsic signature mismatch for `llvm.x86.avx512.vpdpbusd.512`:
  expected `<16 x i32> (<16 x i32>, <16 x i32>, <16 x i32>)`,
  found    `<16 x i32> (<16 x i32>, <64 x i8>, <64 x i8>)`
error: could not compile `quantization` (lib)
```

qdrant's vendored `quantization` crate calls an AVX-512 intrinsic whose
LLVM signature changed under this revision's rustc. This is why qdrant was
absent from every binary cache. `whisper-cpp-vulkan` builds cleanly, so the
speech-to-text half of that worktree is unaffected.

Anything depending on qdrant is blocked until nixpkgs moves or the crate is
patched. Note that the usual fallback, pgvector, is not available either:
this fleet runs no PostgreSQL (every service uses SQLite).

### The Miniflux failure is a missing secret, not a defect

The build stops in sops-nix manifest validation on
`caddy/watch-basic-auth-hash`, the basic-auth secret for
`watch.jeiang.dev`. Failing at build time rather than activation is the
safe outcome: a missing secret cannot take the edge down at runtime.

That secret exists only because changedetection.io has no OIDC and was
gated with basic auth at the edge. Routing it through netbird-proxy
instead removes the secret, the new auth pattern, and this failure.

## Authentication: Pocket ID has no forward-auth endpoint

Recorded because it shaped several decisions and will recur. Pocket ID
exposes no endpoint that answers a Caddy `forward_auth` subrequest, so
"gate it behind Pocket ID at the edge" is not available for services
lacking native OIDC. Two independent implementation attempts hit this and
resolved it inconsistently (one left the service mesh-only, the other
added basic auth).

The settled answer is **netbird-proxy**, which authenticates via Pocket ID
and, per ADR 0002, is publicly reachable on its own `:443`. That gives
per-user SSO from any browser without requiring the NetBird client, and it
is the mechanism for anything without native OIDC.

A caveat for Gatus specifically: it is currently placed on legion-node2,
alongside both netbird-proxy and Pocket ID. A node2 failure would remove
the status page, its exposure path, and its authentication at once --
precisely when it is wanted. It belongs on a different node from the one
serving its access path.

Because netbird-proxy supplies authentication, native OIDC stops being a
selection criterion. That removes the only reason to prefer Miniflux --
PostgreSQL-only -- over `services.freshrss` or `services.yarr`, both
SQLite-backed and both present in the pinned nixpkgs.

## Settled: keep as is

The infrastructure audit recommended **no swaps**. Every current choice was
checked against its 2026 alternatives and confirmed both actively maintained
and correctly chosen for this fleet's constraints: Caddy, CrowdSec, Blocky,
NetBird, Pocket ID, the VictoriaMetrics/VictoriaLogs/Grafana/vmalert/
Alertmanager stack, restic, sops-nix, garret, and deploy-rs.

Two findings worth recording because they contradict common assumptions:

- **deploy-rs is actively maintained**, with feature and bugfix commits
  through August 2026. Its magic rollback is a real safety property that
  plain `nixos-rebuild --target-host` lacks, and it matters for a single
  operator with no on-call backup. Colmena is a legitimate alternative but
  trades that rollback away for config ergonomics; clan is a framework
  migration, not a swap.
- **The flake architecture is right, not half-finished.** It is not
  "halfway to dendritic" — it never attempted topic-based self-registering
  composition, and DESIGN.md's centralized-with-asserts goals actively
  conflict with dendritic's premise. The service inventory's flat-data-plus-
  asserts shape is the correct tool for cross-host allocation data, since
  NixOS options cannot read another host's configuration during evaluation.

The local inference stack also stays. llama.cpp plus llama-swap on Vulkan
remains correct for this GPU class: vLLM and SGLang solve a multi-tenant
throughput problem a single-user box does not have, ExLlamaV3 has no AMD
support at all, and Vulkan beat ROCm and vLLM in 2026 RDNA4 benchmarks.

## Rejected

| Rejected | Reason |
| -------- | ------ |
| Jellyfin and media servers | Domain dropped; not being deployed |
| Forgejo / Gitea | GitHub Actions is sufficient for now |
| Vaultwarden | Bitwarden is in use |
| Immich | Not used |
| Paperless-ngx | Not used |
| Frigate | No workload — `camera-ingest` is a store-and-forward phone-upload relay, not a live RTSP feed |
| Outline | Duplicates the Hermes git-repo knowledge base, with a heavier Postgres/Redis/S3 stack |
| Home Assistant on the cloud nodes | A placement problem, not a sizing one: it wants LAN presence and radios a Hetzner VM does not have |
| n8n, Windmill, Activepieces | All three gate SSO behind paid tiers in 2026 — a licensing wall no node size fixes |
| Uptime Kuma | Documented memory leaks against a hard `MemoryMax` means OOM churn; no native OIDC |
| Homepage, Dashy | Redundant with Glance at four to eight times the RAM for the same job |

Dropping Immich and Paperless removed the only case for provisioning a new
node. Recorded for the future in case that changes: Hetzner raised CPX/CCX
prices 2.1-2.75x in June 2026 while CX/CAX rose only ~1.3x, which makes ARM
dramatically cheaper for real memory — a CAX31 (8 vCPU, 16 GiB) at
EUR 20.99/mo against EUR 69.49 for a same-spec CPX42.

## Open: not yet decided

### Legion fleet — fits in existing headroom

All modules confirmed present in the pinned nixpkgs.

| Service | Value | Cost and caveats |
| ------- | ----- | ---------------- |
| Glance | One page for the whole fleet; Go, single binary | <50 MB. No native auth — gate behind Caddy forward-auth to Pocket ID |
| Gatus | Status page and synthetic HTTP/TCP/DNS checks, config-as-code in git | ~30 MB. Complements vmalert rather than duplicating it |
| Miniflux | RSS, native OIDC | 10-30 MB |
| changedetection.io | Page-change notifications, wired to Hermes or Alertmanager | ~100 MB in basic mode; the Playwright path roughly doubles it |

Navidrome and Audiobookshelf also rank well and have modules, but the source
document justified them as complements to Jellyfin. That premise is gone —
they now stand or fall as standalone music and audiobook servers.

### Artemis — placement, not sizing

| Service | Value | Requires |
| ------- | ----- | -------- |
| Qdrant | Vector database for Hermes retrieval and memory; Rust, no GPU | Lowest integration cost of anything surveyed |
| whisper.cpp server | Telegram voice notes become a Hermes tool call; Vulkan-accelerated | Already in this box's toolchain |
| Open WebUI | Wants to sit next to the inference engine it talks to | — |
| Apollo (Sunshine fork) | Would remove the `hyprctl eval` per-client resolution hack in `modules/nixos/sunshine.nix` | No nixpkgs package — packaging becomes yours to maintain. Deferred: maintaining a package to remove one hack is a poor trade |

### Flake improvements

- Wrap the service inventory in `lib.evalModules` with submodule types, for
  typo-catching only. The flat-data shape stays; this just adds a schema.
- Adopt `nix-unit` for the currently untested pure logic in the inventory's
  derivation functions.

### Worth revisiting independently

ADRs 0008 and 0011 adopted Determinate Nix before the 2026 governance
turmoil (the mandatory-installer change and a failed Steering Committee
no-confidence vote). Not an automatic migration, but the assumptions those
ADRs were written under have shifted, and community sentiment has moved
toward Lix.

## Known gaps, unaddressed

The infrastructure audit found the real weaknesses are process rather than
tooling. vulnix now covers the first. The rest remain open:

- No disaster-recovery restore testing. Nothing verifies a backup restores.
- No S3 object-lock or append-only enforcement on the Mega S4 bucket, so
  nothing stops a compromised host from destroying its own backups.
- No log-based alerting — vmalert covers metrics, LogsQL rules are unused.
- No secret rotation tracking; sops-nix has no expiry mechanism.

## Corrections

Two claims made during this survey were wrong and are corrected here so the
documents are not read as endorsing them:

- `modules/nixos/llama-swap.nix` was described as a hand-rolled unit that
  upstream now provides. It already consumes the upstream
  `services.llama-swap` module. Its remaining lines are the model-fetch unit
  — custom for a documented reason, keeping tens of gigabytes of GGUF out of
  the system closure — plus GPU access overrides. There is no cleanup
  available there.
- `candidates-apps.md`'s "Notes on verification gaps" section lists apps it
  could not confirm had nixpkgs modules, among them Karakeep, Readeck,
  Memos, Navidrome, Audiobookshelf and Open WebUI. Most of those modules do
  exist in the pinned revision, confirmed directly. Trust the verified
  claims in this file over that section.
