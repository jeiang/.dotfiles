# Flake Architecture vs 2026 Paradigms

Evaluation of this flake's architecture against how the Nix community builds
personal/homelab flakes as of August 2026. Written from a full read of
`flake.nix`, `justfile`, `docs/DESIGN.md`, `docs/OPERATIONS.md`, `docs/adr/*`,
`AGENTS.md`, `modules/hosts/legion/default.nix`,
`modules/hosts/legion/_service-inventory.nix`, `modules/nixos/shared/default.nix`,
`modules/parts.nix`, `modules/checks.nix`, `modules/deploy.nix`,
`modules/schemas.nix`, `modules/devshell.nix`, `modules/nixos/hermes-ops/default.nix`,
`modules/nixos/backups/default.nix`, `modules/packages/{environment,caddy,hath}.nix`,
and `.github/workflows/*.yml`, plus current web sources (cited inline).

Format per topic: **What they do now → Verdict → Reason → Effort.**

---

## 1. Module structure: flake-parts + import-tree, `flake.nixosModules.*`

**What they do now.** `flake.nix` is minimal: inputs plus
`flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules)`.
Under `modules/`, files are organized by **output type / role**, not by
topic: `modules/hosts/<host>/default.nix` (host assembly), `modules/nixos/<service>/default.nix`
(one `flake.nixosModules.<name>` per reusable module), `modules/packages/<name>.nix`
(one `perSystem.packages.<name>` per package), plus flat top-level files
(`modules/parts.nix`, `modules/checks.nix`, `modules/deploy.nix`, `modules/schemas.nix`,
`modules/devshell.nix`, `modules/theme.nix`). Host files import their pieces
explicitly and verbosely: `modules/hosts/legion/default.nix`'s
`legionConfiguration` has a hand-written `imports = [self.nixosModules.base
self.nixosModules.sharedConfiguration self.nixosModules.sops ...]`, and
`mkLegionSystem` builds up a module list with a `lib.optional (...) self.nixosModules.X`
line per optional service, each with a comment explaining the gating
condition. `modules/parts.nix` hand-declares `flake.lib`/`flake.darwinModules`
as `lazyAttrsOf raw`/`deferredModule` options specifically so more than one
file can contribute to them without flake-parts' freeform-uniqueness error.

**Verdict: KEEP (this is not the dendritic pattern, and that is fine).**

**Reason.** import-tree is used here purely as a directory auto-walker —
"don't hand-list every file in `modules/`" — while the actual architecture
stays classic flake-parts: modules organized by what they *are*
(host/service/package), each exporting a named `flake.nixosModules.<x>`
output, composed by explicit host-level `imports` lists. That is a
legitimate, independently-established idiom (this predates and is separate
from the dendritic pattern) and is exactly what `docs/DESIGN.md`'s "Module
Boundaries" section documents and enforces. The dendritic pattern was coined
and documented by Shahar "Dawn" Or (`mightyiam`) — origin thread
<https://discourse.nixos.org/t/the-dendritic-pattern/61271> (2025-03-07),
canonical spec at <https://github.com/mightyiam/dendritic> — with `import-tree`
(Vic's own tool) as the enabling mechanism, not the pattern's origin. It is a
different, stricter discipline than what this repo does: *every* `.nix` file
except entry points is itself a feature-scoped module, organized by
**topic/aspect** rather than host or output type; lower-level modules
(NixOS/darwin/home-manager) are held as declared **option values** under the
flake's own namespace (e.g. `nixos.modules.audio`) instead of passed through
`specialArgs`; and composition happens by files existing on disk, not by any
file writing an `imports = [...]` list. mightyiam's own README frames three
things as anti-patterns/hybrid-adoption markers: relying on flake-parts'
built-in `flake.modules` instead of a self-declared option namespace, still
threading values through `specialArgs`/`extraSpecialArgs`, and giving every
module a unique name instead of merging same-named fragments. This repo does
all three "hybrid" things and is not attempting not to — `modules/parts.nix`
hand-declares `flake.lib`/`flake.darwinModules` as ad hoc options rather than
a dendritic feature namespace, and `modules/hosts/legion/default.nix` passes
per-node config through explicit `specialArgs`-equivalent module arguments
(`hermesOps.tier1Units = hermesOpsTiers.${name}.tier1;` etc.), the opposite
of dendritic's top-level-`config` sharing. So this flake is not "halfway
dendritic" as a transitional state — it never started down that path, and
given the design goals in DESIGN.md (single point of truth for service
placement, explicit per-host reasoning, assert-checked invariants), going
further dendritic would actively fight those goals: dendritic's core promise
(no host file has to know what's imported; everything self-registers by
aspect) is the opposite of "one central inventory decides what goes on which
node, with comments justifying each gate." This is not merely this repo's
own framing — 2026 community discussion of the pattern is itself split on
exactly this point: Benedikt Ritter's 2026-05-11 review
(<https://britter.dev/blog/2026/05/11/exploring-the-dendritic-nix-pattern/>)
flags that flake-parts+import-tree's indirection makes tracing harder than
plain grepping, and a 2026-02-08 Discourse thread
(<https://discourse.nixos.org/t/search-for-best-dotfiles-structure-dendritic-edition>)
reports a user going "full dendritic" found complexity grew disproportionate
to their actual needs and settled on a pragmatic hybrid instead — i.e. the
2026 community's own take is that dendritic suits large/complex configs and
is often overkill for smaller ones, not that every import-tree user should
adopt it. Both `flake-parts` (github.com/hercules-ci/flake-parts, 1,448
stars, pushed 2026-08-01/21) and `import-tree` (github.com/vic/import-tree,
322 stars, pushed 2026-07-17/21) remain actively maintained in 2026 with low
open-issue counts, so there's no maintenance-risk reason to move either
direction. Alternatives surveyed and rejected: **snowfall-lib** is
**effectively unmaintained** as of 2026 — its own README added a "Call For
Maintainers" banner in a 2026-07-17 commit stating it "has been effectively
unmaintained for some time now" and inviting a new maintainer
(github.com/snowfallorg/lib) — ruling it out entirely regardless of fit.
**flake-utils-plus** is maintained but low-velocity (real commits as
recently as 2026-05-23, not archived) yet is widely treated in the community
as superseded by flake-parts for anything beyond trivial per-system output
generation (e.g. <https://ayats.org/blog/no-flake-utils>). **haumea**
(nix-community/haumea, maintainer @figsoda, actively pushed 2026-08-20) is a
lower-level filesystem-to-attrset loader, explicitly not a NixOS-module or
flake-parts competitor — it solves the same "don't hand-list files" problem
import-tree already solves here, so adding it would be redundant.
**nixos-unified** (srid/nixos-unified) is maintained but low-velocity (last
commit 2026-04-23, ~4 months stale) and occupies similar opinionated
auto-wiring territory to snowfall-lib; it offers nothing this flake's
DESIGN.md-driven explicit-boundary approach needs.

**Effort.** N/A — no change recommended. If the repo ever wants dendritic
for a *new, self-contained* area (e.g. `modules/darwin/`, which is already
smaller and less centrally-gated than Legion), that could be evaluated
independently later; it should not be retrofitted onto the Legion inventory
path.

---

## 2. The service inventory pattern (`_service-inventory.nix`)

**What they do now.** `modules/hosts/legion/_service-inventory.nix` is a
529-line data file: a plain attrset per node listing its placed services,
each with `name`, `publicHostnames`, `firewall`/`firewallPortRanges`/
`publishedPorts`, `stateful`, and (for stateful services) `volume`/
`backupSet`/`backupPauseUnits`. Four `assert lib.assertMsg` checks at the
bottom enforce global invariants (exactly one edge node, no duplicate public
hostname, every stateful service has a volume, every backup set is a subset
of its volume mountpoint). `modules/hosts/legion/default.nix` then *derives*
from this data: firewall port lists (`firewallPortsFor`), `fileSystems`
mounts, `backups.jobs`, and which optional `flake.nixosModules.*` to import
per node (a chain of `lib.optional (lib.any (s: s.name == "X") node.services)
self.nixosModules.X`). The Legion-inventory shape is separate from (and
deliberately not) the `options.hermesOps.*`/`options.backups.jobs` pattern
used one layer down: `modules/nixos/hermes-ops/default.nix` and
`modules/nixos/backups/default.nix` each *do* expose a typed
`lib.mkOption`/`submodule` surface (`options.backups.jobs = lib.mkOption {
type = lib.types.attrsOf jobType; ...}`) that host config *populates*, rather
than services self-registering.

**Verdict: KEEP the inventory-as-data-file shape; it is already close to the
better community idiom, not a naive god-object.**

**Reason.** The failure mode "service inventory becomes an unmaintainable
god-object" is real, but the two usual fixes — (a) let every service module
self-register into a shared attribute (haumea/dendritic-style
auto-collection) or (b) model the inventory as `options.services.<name> =
lib.mkOption { type = submodule {...}; }` with each service module setting
its own entry — both trade away exactly the property DESIGN.md calls out as
load-bearing: *"Service placement belongs in the central Legion inventory.
Exactly one node owns each stateful service, and moving it is an explicit
state migration rather than scheduler-driven failover."* A self-registering
or submodule-typed design distributes the placement decision back into each
service module (or requires threading `config` across every node's module
set to read other nodes' option values, which NixOS's per-machine
evaluation model does not support at all — you cannot read node2's `config`
while evaluating node4). This repo's actual problem statement — "which node
runs what, with global invariants like no duplicate hostnames and no
orphaned stateful service" — needs a single flat data structure evaluated
once *before* any host's NixOS module system runs, which is precisely what
`_service-inventory.nix` is: a plain attrset with asserts, imported by
`legion/default.nix` and fed into `nixosSystem` module lists, not a NixOS
option evaluated inside any host. That is the correct shape for
cross-host allocation data; NixOS modules/options are the right tool for
per-host *configuration surface* (which `backups.jobs` and `hermesOps.*`
already do one layer down, correctly). What would make it a god-object is
growing unrelated concerns into the same 529 lines — e.g. baking actual
Caddy site config, DNS content, or systemd unit definitions into inventory
entries instead of names/ports/paths. Today it stays disciplined about that:
`publicHostnames` is a plain string list consumed by `modules/nixos/edge/`
to *generate* Caddy config, not Caddy config itself; `firewall` entries are
`{port; proto; scope;}` triples, not raw `networking.firewall.*` values.
**Concrete improvement worth making, not a rewrite:** the assert-based
validation is good but currently mixes "structural invariant" (no duplicate
hostname) with "shape invariant" (every entry has `stateful`/`firewall`
keys, spelled correctly) with zero static typing — a typo like
`fireawll = [...]` on a new service entry silently no-ops instead of
erroring, since the inventory is `{lib}: attrset` with no NixOS `mkOption`
type checking it. That is worth tightening with a `lib.types.submodule` used
purely as a *validator* (evaluated via `lib.evalModules` at the top of
`_service-inventory.nix`, not wired into any `nixosSystem`), which gets
typo-catching and default values without touching the "central inventory,
explicit migration" property at all. Sketch:

```nix
# _service-inventory.nix, validating (not option-surfacing) the shape
{lib}: let
  portType = lib.types.submodule {
    options = {
      port = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
      scope = lib.mkOption {type = lib.types.enum ["public" "private"];};
    };
  };
  serviceType = lib.types.submodule ({name, ...}: {
    options = {
      name = lib.mkOption {type = lib.types.str; default = name;};
      publicHostnames = lib.mkOption {type = lib.types.listOf lib.types.str; default = [];};
      firewall = lib.mkOption {type = lib.types.listOf portType; default = [];};
      stateful = lib.mkOption {type = lib.types.bool; default = false;};
      # volume/backupSet/backupPauseUnits as today, typed instead of duck-typed
    };
  });
  nodeType = lib.types.submodule {
    options = {
      edge = lib.mkOption {type = lib.types.bool; default = false;};
      services = lib.mkOption {type = lib.types.listOf serviceType; default = [];};
    };
  };
  validated = (lib.evalModules {
    modules = [{options.inventory = lib.mkOption {type = lib.types.attrsOf nodeType;};} {inventory = rawInventory;}];
  }).config.inventory;
in
  # existing asserts unchanged, operating on `validated` instead of a raw attrset
  validated
```

This is additive (roughly 30-40 lines), keeps every existing consumer
(`legion/default.nix`) unchanged since it still returns a plain attrset
shape, and converts "silent typo → wrong firewall rule in production" into
an eval-time type error. Do not go further than this — do not turn the
inventory into a NixOS option tree that hosts "opt into," since that is the
self-registration design this section argues against.

**Effort.** Small (half a day): write the submodule types, swap the file's
final `inventory` for `validated`, run `just check`.

---

## 3. Deployment: deploy-rs vs colmena / clan-core / comin / nixos-rebuild-ng

**What they do now.** `deploy-rs` (`inputs.deploy-rs`, locked
2026-08-10), invoked via `just deploy <system>` /
`just deploy-legion`, with `flake.deploy.nodes` built in
`modules/hosts/legion/default.nix` (magic rollback via the deploy-rs canary,
a dedicated `deploy` system user with a narrow NOPASSWD sudo rule for
`activate-rs` and the rollback `rm`, ADR 0001 explicitly treats the
deployment identity as privileged and accepts that risk rather than
containing it). `nixos-anywhere` handles first-boot provisioning
(`just clean-deploy`), and `modules/schemas.nix` hand-writes a `schemas.deploy`
entry so Determinate Nix's `nix flake show` can render the deploy-rs output
sanely.

**Verdict: KEEP deploy-rs for this fleet; do not migrate to colmena or clan
right now.**

**Reason.** deploy-rs (serokell/deploy-rs) is **actively maintained**, not
merely tolerable-but-stale: last commit 2026-08-10, with real feature work
landing through 2026 (client-side `preActivate`/`postActivate` hooks
2026-07-06, env-var support 2026-06-19, `--skip-offline` 2026-04-15, an
activation-confirmation race fix 2026-07-11). It carries a real backlog (70
open issues, 43 open PRs) and ships no tagged releases — it's consumed
purely as a pinned flake input, same as this repo already does
(`flake.nix`'s `deploy-rs.url`) — but neither is evidence of neglect for a
tool in this ecosystem. No 2026 Discourse thread, issue, or blog post
declaring it unmaintained turned up in this research; the opposite signal
exists — a 2026-08-11 Discourse thread has a user calling themselves "#1
`deploy-rs` shill," describing exactly this repo's workflow (provision with
nixos-anywhere, manage day-2 with deploy-rs) as the standard 2026 pattern
(<https://discourse.nixos.org/t/opentofu-terraform-provider-for-nixos/79530>).
One concrete operational risk worth flagging regardless of tool choice: an
open 2026-08-02 deploy-rs issue describes a failed activation that can leave
`switch-to-configuration` holding a lock and poisoning subsequent deploys on
that host — worth a one-line runbook note ("if a deploy hangs, check for a
stuck `switch-to-configuration` on the target and kill it before retrying")
rather than a tool change. The two most-discussed 2026 alternatives solve a
different problem than this repo has: **colmena**
(now nix-community/colmena, the old zhaofengli/colmena URL 301-redirects
there) is actively committed (2026-08-14) but **still pre-1.0** — its own
unstable manual states current features are targeting an eventual v0.5, and
tagged releases stop at v0.4.0 from 2023-05-15, so anyone pinning to a
release rather than flake HEAD runs three-year-old code. It's a reasonable
deploy-rs substitute in shape (parallel deploys, tag-based host selection)
but offers nothing this flake is missing today, and switching would be pure
migration churn (rewrite `flake.deploy.nodes`/`justfile` targets, re-verify
the sudo/rollback flow against colmena's own activation mechanism) against
a less mature target. **clan-core** (canonical repo is the self-hosted
git.clan.lol, actively updated daily, calendar-versioned "26.05") is
genuinely more ambitious — declarative inventory, its own secrets/"vars"
system (see §4), peer-to-peer fleet management — and notably **already
builds on nixos-anywhere and disko internally**, i.e. it wraps the same
provisioning primitive this repo already uses rather than replacing it. But
it is a different, heavier framework, not a drop-in deploy tool: adopting it
means re-platforming secrets, module composition, and host bootstrapping all
at once. That matches a 2025-era migration writeup this research surfaced
(<https://blog.stark.pub/posts/clan-migration/>), which describes "Clan and
Dendritic Architecture" as one combined migration project, not an isolated
deploy-rs swap — clan is an all-or-nothing adoption, not a targeted fix for
one weak link. **comin** (nlewo/comin) has a healthy, roughly-monthly
release cadence (v0.14.0 2026-07-19) but is GitOps **pull**-based: an agent
runs on every target host and polls a git remote to self-apply, the inverse
of this repo's push-from-macOS model. Adopting it means running a comin
service and granting outbound git access on all six hosts for no benefit
here, and it drops the "operator runs `just deploy` from macOS with
`--remote-build`, verifying staged nodes" workflow `docs/OPERATIONS.md`
documents as deliberate (*"the fleet-wide deployment helper is not a
substitute for staged node verification"*) — a philosophy change, not a
tooling swap. **nixos-rebuild-ng** (the Python rewrite, now the default
`nixos-rebuild` implementation in nixpkgs) is under very active 2026
development — `--elevate={none,sudo,run0}` merged 2026-07-07, `nom` output
support and fish completions landed in August 2026 — and does confirm
`--target-host`/`--build-host`/`--use-substitutes` are all native there now.
But it operates on exactly one host per invocation with no fleet
enumeration, no parallel apply, and no magic rollback; an open 2026-07-11
nixpkgs enhancement request ("copy closure to `--target-host` while
building") shows gaps remain even at the single-host level. Using it for
this fleet would mean hand-rolling the parallel/rollback logic
`deploy-legion` and ADR 0001's canary already give for free — a downgrade,
not a lateral move. **krops** is dormant (last push 2025-12-09, ~8.5 months
stale) and pre-flakes in design; not a serious contender. `nixos-anywhere`
for initial bootstrap stays correct and current (last commit 2026-08-19,
the de facto standard for kexec-based provisioning, and the primitive
clan-core itself builds on) — this repo already uses it exactly as intended
via `just clean-deploy`.

**Effort.** N/A — no migration recommended. Worth a small runbook addition
(the stuck-activation-lock note above) and a standing watch: if deploy-rs's
backlog keeps growing with no further commits through 2027, colmena is the
lowest-friction fallback once it clears 1.0 — re-evaluate then, not now.

---

## 4. Secrets: sops-nix vs agenix vs clan vars

**What they do now.** `sops-nix` (locked 2026-08-10), with the sharding
discipline from ADR 0006: one `secrets.yaml` per consuming module directory
(e.g. `modules/nixos/hermes/secrets.yaml`), each encrypted only to the admin
plus the specific host(s) that consume it — `modules/nixos/shared/default.nix`
uses `sops.secrets."passwords/aidanp"` with `neededForUsers = true`,
`modules/nixos/backups/default.nix` uses its own `secrets.yaml` for the
restic password/S4 credentials.

**Verdict: KEEP sops-nix.**

**Reason.** sops-nix (Mic92/sops-nix, 3,121 stars, pushed 2026-08-16, merged
PRs as recently as 2026-08-10) remains the community default for setups with
more than a couple of services each wanting a bundle of related secrets, and
scales better than agenix specifically for the "many services, many hosts,
partial sharing" shape this repo has — which is exactly ADR 0006's
per-module-shard-with-selective-recipients design. **agenix**
(ryantm/agenix) trades that scaling for a simpler one-file-per-secret,
SSH-key-only identity model that suits smaller setups, and its 2026
maintenance signal is visibly weaker than sops-nix's — no commits since
2026-02-04 at time of writing, roughly six and a half months stale; it would
be both a functional downgrade (loses the per-path creation-rule scoping
ADR 0006 depends on) and a maintenance-risk lateral move to adopt fresh
today. **clan vars** has matured past "design proposal" since its 2025-03
Discourse announcement: clan's docs now ship under a stable release path
(25.11, with 26.05 flagged as newly out) and vars has its own non-experimental
reference/guide section (<https://clan.lol/docs/unstable/guides/vars/vars-concepts>).
It is still explicitly a pluggable *interface* over swappable backends —
sops is its own documented default backend
(<https://clan.lol/docs/25.11/guides/vars/sops/secrets>) — rather than a
competing secret store, and its guides all assume clan's broader
inventory/services model; there is no 2026 documentation found endorsing
standalone (non-clan) production use. It is coupled to adopting clan-core
more broadly (see §3), which this repo has no other reason to do. There is
no case for switching secrets backends independent of a full clan migration,
and §3 already concludes clan migration is not warranted.

**Effort.** N/A.

---

## 5. Multi-host sharing, per-host overrides, avoiding a god-object

**What they do now.** Shared config lives in named
`flake.nixosModules.*` (`base`, `sharedConfiguration`, `sops`, `netbird`,
`backups`, `hermes-ops`) imported unconditionally per fleet
(`legionConfiguration`'s fixed `imports` list); per-node variance is
expressed as data consumed by that shared code (`_service-inventory.nix`,
`hermesOpsTiers`, `legionNodes` IP table) rather than as per-host
conditionals sprinkled through shared modules. `modules/nixos/shared/default.nix`
is genuinely fleet/desktop-shared (users, ssh, zram) and stays small (48
lines). Host-specific behavior that is *intentionally* not generalized is
called out explicitly in `docs/DESIGN.md`'s "Intentional Host Decisions"
list (Artemis's custom kernel, btrfs RAID0 striping, PCI-address GPU
symlinks) rather than being hidden inside a shared module with host-name
conditionals.

**Verdict: KEEP.** This is one of the stronger parts of the repo and worth
calling out as already right, not just "not wrong." The god-object risk in
multi-host flakes almost always comes from one of two places: (a) a shared
module accreting `if hostName == "X" then ... else ...` branches, or (b) a
single "everything" data file that mixes allocation, configuration values,
*and* narrative decisions. This repo avoids (a) entirely — grep shows no
`config.networking.hostName ==` branching inside `modules/nixos/shared/`.
It avoids (b) by keeping `_service-inventory.nix` scoped to placement/
firewall/backup/volume facts only (§2) and pushing the *why* into
`docs/DESIGN.md`/ADRs rather than into inline conditionals. The one place
worth flagging before it grows further: `hermesOpsTiers` currently lives
inline in `modules/hosts/legion/default.nix` (not in
`_service-inventory.nix`, with an explicit comment explaining why it's kept
separate — hermes-ops is cross-cutting fleet policy, not a placed service).
That's a reasonable call today at ~50 lines, but if a second cross-cutting
per-node classification table shows up (a third "this data doesn't fit the
service-inventory shape" table), that's the signal to give
`legion/default.nix` its own small `_hermes-ops-inventory.nix` companion
file rather than letting `default.nix` (578 lines) keep absorbing them
inline.

**Effort.** N/A now; watch-item only.

---

## 6. Testing: nixosTest, nix-unit, build-vm, CI matrix, `nix flake check` scaling

**What they do now.** No `nixosTest`/`pkgs.testers.nixosTest` VM tests
exist anywhere in `modules/`. No `nix-unit` for the substantial amount of
pure-Nix logic in `_service-inventory.nix`'s derivation functions
(`firewallPortsFor`, `firewallPortRangesFor`) or `modules/hosts/legion/default.nix`'s
`mkWan`/`nodeHostname`. Validation is `nix flake check --impure --keep-going`
(`just check`) plus CI's `build` job, which dynamically discovers
`checks.x86_64-linux` attribute names (`modules/checks.nix` maps every
`self'.packages` and every `self.nixosConfigurations.*` to a
`package-*`/`toplevel-*` check, adds a `statix` check) and fans them into a
GitHub Actions matrix (`max-parallel: 10`), collapsing all `deploy-*` checks
into one shared leg since they overlap in closure. A separate `all-checks`
job aggregates matrix results into one required status. `AGENTS.md`
explicitly steers away from `nix flake show` as a validation path because it
enumerates platform-invalid outputs.

**Verdict: ADOPT nix-unit for the inventory-derivation logic; hold off on
nixosTest and nix-fast-build.**

**Reason.** The CI matrix-discovery approach here (`discover` job emitting
`checks.x86_64-linux` attr names via a cheap `nix eval --apply
builtins.attrNames`, `build` fanning them into a `max-parallel: 10` matrix,
`all-checks` as the single required gate) is already the community-standard
shape for "evaluate/build N things cheaply in CI" as of 2026, not merely
adequate: `wimpysworld/nix-config` (715 stars, pushed 2026-08-21) implements
the identical pattern — a lazy `nix eval <flake>#<output> --apply
builtins.attrNames --json` inventory step feeding `strategy.matrix.target:
${{ fromJSON(...) }}` in downstream jobs
(<https://github.com/wimpysworld/nix-config/blob/main/.github/workflows/builder.yml>).
This convergent design is not a coincidence: `nix flake check` itself has a
known, still-open 2026 eval-caching gap — it evaluates outputs directly
instead of through the same `EvalCache` cursors other Nix commands use, so
repeated `flake check` runs get zero cache benefit and large flakes can hit
30-50 GB RSS, per open upstream issue
<https://github.com/NixOS/nix/issues/13470> (no merged fix as of this
writing). The community workaround converging in 2026 is exactly what this
repo and wimpysworld/nix-config both do independently: don't lean on `nix
flake check` as the CI mechanism for a large multi-host flake, discover
attrs cheaply and build them directly. `AGENTS.md`'s explicit steer away
from `nix flake show` (enumerates platform-invalid outputs) is the same
instinct applied one step further. That's a solid, currently-idiomatic
setup and needs no framework swap. **nix-fast-build** (Mic92/nix-fast-build,
just tagged v2.0.0 on 2026-08-21, wraps `nix-eval-jobs` to evaluate flake
attributes in parallel and start builds as each evaluation completes rather
than waiting for the whole eval phase) is explicitly positioned in 2026
community discussion as *the* practical answer to the same `flake check`
caching gap above, and is a real, actively-maintained tool, not a dead end —
but it solves a problem this repo doesn't clearly have yet: its own
`discover`+`build` split already gets most of the same benefit (parallel,
isolated legs, no reliance on `flake check`'s broken caching), and swapping
the discovery/build mechanism for a new external tool is a real rewrite of a
CI setup already tuned through at least one documented incident (the OOM
comment in `ci.yml`). Revisit if evaluation time itself (not build/
substitution time) becomes the bottleneck — nix-fast-build's own reported
numbers (one example cut a check from ~1:50 to ~10s) suggest real headroom
exists if that day comes. What actually *is* missing: `_service-inventory.nix`
and `legion/default.nix` contain nontrivial pure functions with real
invariants (`firewallPortsFor`/`firewallPortRangesFor` proto/scope
filtering, `backupSetViolations`'s prefix-matching, `mkWan`'s route shape)
that are currently only exercised indirectly by whether the full NixOS eval
happens to succeed — a change that breaks one of these functions in a way
that still evaluates (e.g. `firewallPortsFor` silently returning an empty
list for a typo'd `proto`) would pass `just check` outright. **nix-unit**
(nix-community/nix-unit, actively maintained with a steady release cadence —
v2.35.1 on 2026-07-23, pushed 2026-08-21 — running `lib.debug.runTests`-shaped
attrsets directly through the Nix evaluator's API) is the standard 2026 tool
for exactly this: pure-function unit tests with no NixOS eval overhead, fast
enough to run on every PR. This is a genuine coverage gap, not a
nice-to-have: the inventory's own assert messages already prove the authors
know these invariants matter; nix-unit would let those invariants (and the
derivation functions that feed the firewall/backup/volume outputs) be
tested directly instead of only transitively through whether four full
`nixosSystem` evaluations happen to succeed. **`nixosTest`** VM tests are a
real gap too (no test verifies, e.g., that the edge node's Caddy actually
proxies to netbird-server, or that a mount-guarded service refuses to start
without its volume) but are a materially bigger lift — building and booting
full NixOS VMs per service — and this repo's CI is already the slow/
expensive part operationally (documented OOM history); adding VM tests
should wait until nix-unit coverage of the cheaper pure-logic layer is in
place. `nixos-rebuild build-vm`/`build-vm-with-bootloader` remain
actively touched upstream in 2026 (nixpkgs PRs merged 2026-08-13 and
2026-07-07) but are not used here and not clearly needed given the existing
staged-verification discipline in `docs/OPERATIONS.md`.

**Effort.** Medium (1-2 days): add `inputs.nix-unit`, write unit tests for
`firewallPortsFor`/`firewallPortRangesFor`/`backupSetViolations`/`mkWan`/
`nodeHostname`, wire a `nix-unit` check into `modules/checks.nix` and the CI
matrix (it will show up in `discover`'s dynamic list for free once added as
a `checks.x86_64-linux` attr).

---

## 7. Package-Wrapper Policy: `nix-wrapper-modules` vs `symlinkJoin`/`wrapProgram`/`.override`

**What they do now.** `docs/DESIGN.md`'s "Package-Wrapper Policy" section
and `modules/packages/{environment,fish,ghostty,git,helix,mangohud,starship}.nix`
use `inputs.wrapper-modules.lib.wrapPackage` (BirdeeHub/nix-wrapper-modules,
locked 2026-06-22) to bake in flags/config/env for CLI tools —
e.g. `modules/packages/environment.nix` wraps the fish package to set
`EDITOR` and `shellPath`. The policy is explicit about scope: prefer
wrapping over a separate hjem-managed dotfile "when the program accepts an
explicit config-file flag, startup command, or environment variable," only
migrate a program once the launch path is certain, and downstream modules
consume the wrapped output through the flake rather than raw `pkgs.<name>`.

**Verdict: KEEP, with bus-factor as the only open risk.**

**Reason.** nix-wrapper-modules (github.com/BirdeeHub/nix-wrapper-modules,
413 stars, pushed 2026-08-20, 774+ commits) is a real, actively-developed
tool built specifically to solve "define a wrapped package's config once,
reuse the module shape across NixOS/home-manager/nix-darwin/devenv" — which
is exactly this repo's situation (`environment.nix`'s wrapped fish is
consumed by both the NixOS user shell and, per `modules/devshell.nix`, the
devenv shell). It is young (created 2025-11-06) and its own README states an
explicit long-term goal of transferring to nix-community — i.e. the
maintainer considers it not yet at its intended stability/governance target,
a fair signal that this is still a maturing dependency rather than settled
infrastructure. It is also genuinely niche: 413 stars for a nine-month-old
single-maintainer project is real traction but nowhere near an established
default (home-manager, for comparison, sits over 10,000 stars), and most of
the ecosystem still reaches for plain `wrapProgram`/`symlinkJoin`/
`writeShellApplication` directly rather than a shared wrapper-module
abstraction. None of that changes the verdict for *this* repo, though:
plain `symlinkJoin`+`wrapProgram` or nixpkgs `.override` can do the
individual wraps this repo performs today, but they don't give the reusable,
cross-context module shape nix-wrapper-modules provides, and DESIGN.md's
policy already constrains its use tightly (only when a program takes an
explicit config flag/env var; "once a wrapper exists, downstream modules
reference the wrapped package through this flake" — no silent divergence
between the wrapped and raw package). That is a well-scoped, deliberate
policy, not tool-for-tool's-sake adoption — the repo isn't using it to wrap
everything, only the handful of CLI tools where baking in config/flags
actually simplifies a real multi-consumer situation. The residual risk is
bus-factor on a young single-maintainer tool, not idiom-fit; since the
policy already requires "downstream consumes the wrapped package through
this flake" (i.e., no scattered direct `wrapPackage` calls outside
`modules/packages/`), a future removal would be a contained, mechanical swap
back to `wrapProgram` in the handful of files that use it — acceptable
residual risk for a personal flake, and one the maintainer's own
nix-community-transfer goal, if it happens, would resolve outright.

**Effort.** N/A — no change recommended.

---

## 8. Other 2026 tooling worth adopting or already adopted

| Tool | Status here | Verdict | Reason |
| --- | --- | --- | --- |
| `nixos-anywhere` | Already used (`just clean-deploy`) | KEEP | Community-standard first-boot provisioning tool in 2026; no successor surfaced in this research. |
| Determinate Nix | Adopted per ADR 0008 (Zakkart) and ADR 0011 (NixOS fleet), locked 2026-08-07 | KEEP, but re-read ADR 0008/0011 against 2026 governance news | Determinate Nix and lix have diverged further than "both active, no clear winner" by mid/late 2026. Determinate switched its own installer's *default* away from upstream CppNix on 2025-11-10, then removed the `--prefer-upstream-nix` escape hatch entirely on 2026-01-01, making Determinate Nix mandatory for anyone using their installer (<https://determinate.systems/blog/installer-dropping-upstream/>). The community responded with its own upstream-only installer fork positioned as the new community default, and a Nix Steering Committee vote of no confidence (driven partly by governance/conflict-of-interest concerns over Determinate's SC influence) ended in a 3-3 tie that failed to pass (<https://lobste.rs/s/jai4yu/nix_steering_committee_vote_no>). Sentiment on Discourse (<https://discourse.nixos.org/t/old-nixos-new-nixos-lixos-or-determinate-systems-nixos/78109>) now leans toward lix as "the safest choice" specifically because of this drama, while Determinate retains traction mainly through commercial tooling (FlakeHub, CI actions) this repo doesn't use. This doesn't overturn ADR 0008/0011's stated reasons (owning the installer/upgrade path, `schemas` output support) on its own, but the governance landscape those ADRs were written against has shifted enough that they're worth a deliberate re-read rather than treating the 2026-08 lock date as still-fresh validation. |
| `nix flake update --commit-lock-file` / lockfile bots | Already adopted (`.github/workflows/update-flake-inputs.yml` uses `DeterminateSystems/update-flake-lock`) | KEEP | This remains the standard approach in 2026; the workflow's own selective per-input opt-in design (scheduled auto-bump only for the three zero-risk app inputs, everything else `workflow_dispatch`-gated) is more careful than the community default of bumping everything, and is worth keeping as-is. |
| `nvfetcher` / `npins` | Not used | KEEP not using | Both exist to pin *non-flake* sources cleanly; every non-nixpkgs input in `flake.nix` is already a flake input (including the `flake = false;` homebrew tap ones, which flake's own input-locking already pins via `flake.lock`). There is no unpinned/ad-hoc source in this repo that either tool would improve. |
| Flake output schemas (`flake-schemas`) | Already adopted (`modules/schemas.nix`, custom `deploy`/`diskoConfigurations` schema entries) | KEEP | Still Determinate-Nix-only in 2026 (no evidence found of upstream CppNix/Lix merging schema support); since the fleet already runs Determinate Nix (ADR 0008/0011) this is pure upside with no cost on stock Nix/Lix, exactly as `modules/schemas.nix`'s own comment states. |
| `hjem` | Adopted (`inputs.hjem`, `modules/nixos/hjem/`, `modules/darwin/hjem.nix`) | KEEP | hjem remains actively maintained in 2026 (locked 2026-08-05) and is explicitly a lighter-weight, non-framework alternative to home-manager — a deliberate fit for a repo that otherwise avoids heavy frameworks (no home-manager at all here). No signal found that home-manager is being deprecated in its favor community-wide, but hjem's minimalism matches this repo's stated design philosophy well. |
| `nixos-facter` | Adopted (`just clean-deploy` passes `--generate-hardware-config nixos-facter`) | KEEP | Actively maintained (nix-community/nixos-facter, maintainers @brianmcgee/@Mic92), positioned as the nixos-hardware/nixos-generate-config successor; already the right choice. |

---

## Summary table

| # | Area | Current | Verdict | Effort |
| - | --- | --- | --- | --- |
| 1 | Module structure (flake-parts + import-tree, output-type dirs) | Not dendritic, classic named-module composition | KEEP | — |
| 2 | Service inventory (`_service-inventory.nix`) | Flat asserted data file | KEEP + typed-validator sketch | Small |
| 3 | Deployment (deploy-rs) | Push/SSH/remote-build, magic rollback | KEEP | — (watch-item) |
| 4 | Secrets (sops-nix, sharded) | Per-module `secrets.yaml`, scoped recipients | KEEP | — |
| 5 | Multi-host sharing | Named modules + data-driven variance | KEEP | — (watch hermesOpsTiers growth) |
| 6 | Testing / CI | Dynamic matrix, no unit/VM tests | ADOPT nix-unit; hold nixosTest | Medium |
| 7 | Package-Wrapper Policy | `nix-wrapper-modules`, scoped | KEEP | — |
| 8 | Misc 2026 tooling | nixos-anywhere, Determinate Nix, schemas, hjem, facter, lockfile bot all already adopted | KEEP across the board | — |
