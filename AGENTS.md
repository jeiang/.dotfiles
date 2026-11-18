# AGENTS.md

`cornn-flaek` is a flake-parts + import-tree flake for every host. `main`
is what every host runs.

Hosts: NixOS `artemis` (home server, impermanent root) and the Legion
servers `alda`, `vida`, `zantark`, `peria` (Hetzner Cloud) and `ricklent`
(Linode); nix-darwin `zakkart` (the operator's Mac). A Legion service runs
on its `legion.services.<name>.node`.

## Workflow

- Never commit to `main`; use a branch and a pull request. Commits must be
  signed. Merge with `gh pr merge --auto --merge`. Wait for CI with
  `gh pr checks <n> --watch --fail-fast --interval 30` (no `--required`) as
  a background job, then confirm `gh pr view <n> --json state,mergedAt`.
- Conventional Commits.
- Tools come from the devshell (`.envrc`, or `nix develop -c <cmd>`). In a
  new worktree, copy the gitignored `.pre-commit-config.yaml` symlink from
  the main checkout before the first commit.
- Validate with `just fmt` and `just check`. Everything evaluates in pure
  mode: never add `--impure`. `nix flake show` fails on this flake.
- `just prepush` pushes the changed host systems to garret (the Nix cache)
  so CI does not compile large builds such as the artemis kernel. Run it
  before opening a pull request and after a flake input bump. It needs
  artemis reachable at `artemis.jeiang.vpn` over NetBird.
- Long builds run on artemis:
  `nix build --eval-store auto --store ssh-ng://artemis.jeiang.vpn <installable>`,
  then `garret push` on artemis.
- A command that runs more than once becomes a `justfile` recipe.

## Layout

- `modules/hosts/<host>/`: one host, assembled from modules, with its
  hardware, disko, and secrets. Legion nodes share `modules/hosts/legion/`.
- `modules/<feature>.nix` or `modules/<feature>/`: one feature for every
  class it applies to. It contributes to roles: `nixos.modules.base`,
  `darwin.modules.base`, `shared.modules.base`,
  `shared.modules.workstation` (artemis and zakkart),
  `nixos.modules.artemis`, `nixos.modules.legion`, or
  `nixos.modules.<service>`.
- A Legion service sets `legion.services.<name>` in its feature file (node,
  ports, public ports, Volume, backup set, hostnames);
  `modules/hosts/legion/` derives imports, firewall, monitoring, and
  backups from it.
- `modules/packages/<name>`: a custom package or wrapped program.
  Linux-only packages go in `perSystem.linuxPackages`, darwin-only ones in
  `perSystem.darwinPackages`.
- A secret shard is `secrets.yaml` beside its consumer, or
  `secrets.<consumer>.yaml` for a second one in the same directory.
- `dns/dnsconfig.js`: public DNS. `docs/runbooks/`: procedures.
  `docs/topology/`: generated diagrams.

## Access

- Legion: `<name>.svr.jeiang.dev`. artemis: `artemis.jeiang.vpn`.
- `sudo` needs no password inside an SSH session.

## Rules

### Operator boundary

- Never run `sudo` or reboot a host unless the user permits it for the
  current task. Otherwise give the exact command in fish syntax; wrap POSIX
  one-liners run over SSH in `bash -c '...'`.
- Deploy, `clean-deploy`, `install`, `disko-format`, `just netbird-apply`,
  and any sops change need explicit approval for that action and target.
  Deploy only after the pull request is merged and CI has pushed to garret;
  read `docs/runbooks/deploy.md` first.
- Never print, decrypt, move, or re-key secrets unless the task asks.
- Never change disk layouts, host networking, deploy targets, module
  boundaries, or host names as incidental cleanup. Never destroy or format
  a disk unless the user names the host.
- A merge to `main` reaches every NixOS host as root. Never weaken branch
  protection, the auto-upgrade checks, or garret signing.
- Flag a change that would break a rollback to the previous generation.

### Code

- Comment only a workaround (what is broken and why), one line of context
  the code cannot express, or a one- or two-line purpose note on an obscure
  script. Never write history, measurements, or rejected alternatives.
- Define a shared literal (port, secret name, hostname) once, as a
  `flake.lib` name owned by its module. Address a Legion service through
  `self.lib.serviceAddress`, `serviceMeshAddress`, or `legionAddress`; never
  type a node name.
- Add a typed option only for a value reused across modules or hosts, tuned
  per host, or marking a module boundary.
- Prefer the nixpkgs module for a service.
- A wrapped program keeps its configuration beside the package, and
  consumers use the flake's package, not `pkgs.<name>`.
- Formatting is treefmt (alejandra, deadnix, stylua) plus statix. Lua uses
  tabs.
- A module adds the units it owns to `monitoredUnits`.
- Re-run `just topology` when hosts, networks, or services change.

### State, secrets, backups

- A change to artemis `persistence.*` needs `just migrate-persist` and a
  `--boot` deploy (`docs/runbooks/deploy.md`). Every backup path must be a
  persistence path and must not be or contain a nested subvolume.
- Never edit `.sops.yaml`; follow `docs/runbooks/secrets.md`. A rotated
  secret reaches a process only through its `restartUnits`.
- A Legion host that owns no backup job is not a recipient of the backups
  shard.

### Legion

- Each stateful service has exactly one node. State that must survive a
  server loss uses a Hetzner Volume with `mountGuard`, mounted by an ext4
  label equal to its service key (at most 16 bytes) that is formatted
  before the deploy. Other state stays on the root disk with a `backupSet`.
  ricklent has no Volumes. Moving a stateful service is a state migration.
- Address a Hetzner server disk as `self.lib.hetznerServerDisk`, never
  `/dev/sdX`.
- A new connection between Legion machines over the mesh needs a
  `meshFlows` entry in `modules/netbird-management`. A port another Hetzner
  node reaches over the private network needs a `ports` entry.
- A public opening is `publicPorts` or `publicPortRanges`, plus a rule in
  the Hetzner `legion` Cloud Firewall or ricklent's Linode firewall, which
  the operator changes by hand. Tell the operator.
- Each Hetzner node's drop of NetBird traffic to `172.16.0.0/12` stays in a
  prerouting chain; NetBird's accepts preempt forward and input chains.
- NetBird management is declarative: `just netbird-apply` deletes
  undeclared objects. Run `just netbird-plan` first. Keep the addresses in
  `modules/netbird-peers.nix` when re-enrolling a peer.
- Every CrowdSec credential is an entry in the `crowdsec.bouncers`
  registry; firewall bouncers are named `<node>-firewall`.
- Blackbox probes target private backend addresses, never public URLs.
- Anubis fronts only the static content sites, never a machine client.
- `cache.jeiang.dev` and `cache-push.jeiang.dev` stay DNS-only in
  Cloudflare.
- A new repository or workflow that pushes to garret needs its entry in
  `job_workflow_refs` (`modules/garret/default.nix`).
- garret's units must not start without the index: an empty index makes
  the Pusher delete every bucket object older than 24 hours.
- The portfolio runs unreviewed upstream code: its `IPAddressAllow` stays
  limited to the edge.
- `dns/dnsconfig.js` is applied with full purge on merge. Legion service
  records come from `publicHostnames` through `just dns-nodes`.
- Pocket ID settings are declared in Nix; an undeclared setting takes
  Pocket ID's default.

### artemis

- atrium's listeners never open on another interface. Operator settings
  are atrium database settings, not Nix. A code change reaches artemis by
  bumping the `atrium` input; its own `AGENTS.md` holds its decisions.
- Only `atrium-media-agent` reads or writes `/var/lib/media`.
- qBittorrent: loopback must authenticate, no subnet is whitelisted, and
  the WireGuard endpoint is ricklent's IP, not its name.
- Minecraft enters only through ricklent's stream proxy, never a home
  firewall opening. Its whitelist is declared in Nix.
- Model weights and caches never go in the Nix store.

### zakkart and agent tooling

- Determinate Nix owns Nix: on zakkart `nix.enable = false`, and settings
  go in `determinateNix.customSettings` with `extra-*` keys.
- zakkart applications come from nixpkgs; a Homebrew cask only when no
  working darwin package exists or the app must manage itself.
- Agent skills and instructions change by bumping the `agent-skills`
  input. Entry names come from its `lib.entries`, never from the built
  package.
- The `llm-agents` input's `nixpkgs` must not follow ours.

## CI

- `all-checks` is the only required status.
- Only a `main` run pushes to garret; it then sets each host's
  `system/<host>` commit status, which auto-upgrade reads.
- `dns.yml` previews DNS changes on a pull request and applies them on
  merge. `hcloud.yml` is advisory.
