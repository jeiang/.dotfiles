# AGENTS.md

`cornn-flaek` is a flake-parts + import-tree flake. `main` is what every
machine must run.

| Host | Kind | Role |
| --- | --- | --- |
| `artemis` | NixOS | Headless gaming and streaming box at home. Impermanent btrfs root. Reached over NetBird with Sunshine/Moonlight and hypr-rdp. Also hosts the Hermes assistant and its local model server. |
| `zakkart` | nix-darwin | The operator's MacBook. |
| `legion-node1`..`legion-node4` | NixOS | Hetzner Cloud service nodes. `legion-node1` is the Caddy edge. |

Backwards compatibility matters only for rollback. Flag a change that would
break a rollback to the previous generation; otherwise do not keep old
behavior for its own sake.

## Workflow

- Never commit to `main`. Use a branch and a pull request. `main` is
  protected and requires signed commits. Merge with
  `gh pr merge --auto --merge` after CI passes.
- Use Conventional Commits.
- Repository tools come from the devshell: `direnv` loads `.envrc`, or run
  `nix develop --impure -c <cmd>`.
- Validate with `just fmt` and `just check`. For one host, compare
  `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
  (or `.#darwinConfigurations.zakkart...`) before and after the change. Do
  not use `nix flake show`: it enumerates outputs that are invalid on the
  current system.
- CI evaluates in pure mode. Never add `--impure` to CI; only the devshell
  surfaces are impure.
- In a new git worktree, copy the gitignored `.pre-commit-config.yaml`
  symlink from the main checkout before the first commit.
- A command that runs more than once becomes a `justfile` recipe.
  `just --list` is the recipe index.

## Code rules

- The code describes the system; it does not carry prose. Write a comment
  only for a workaround (what is broken and why), for one line of context
  the code cannot express, or as a one- or two-line purpose note on an
  obscure script. Never write history, measurements, rejected alternatives,
  or "matches X elsewhere" notes. Git history is the archive. A decision
  that constrains future changes goes in this file.
- Define a literal shared between modules (port, secret name, hostname)
  once and reference it. Two services on different hosts may share a value.
- Add a typed option only when a value is reused across modules or hosts,
  tuned per host, or marks a module boundary. No single-call-site options.
- Prefer the nixpkgs NixOS module for a service. Write a custom module only
  when none fits. Run an upstream OCI image only when packaging the
  application is a project in itself; its supporting services stay native.
- Wrapped programs (`nix-wrapper-modules`) keep their configuration beside
  the package. Consumers use the wrapped package from this flake, not
  `pkgs.<name>`. Wrap a program only when every launch path uses the
  wrapper.
- Formatting is treefmt (alejandra, deadnix, stylua) plus statix. Lua uses
  tabs.
- Do not reorganize module boundaries or rename hosts as incidental cleanup.

## Layout

- `flake.nix`: inputs and the `mkFlake` entry point.
- `modules/hosts/<host>/`: host assembly, hardware, disko, facter report,
  host secrets. `modules/hosts/legion/services.nix` declares the
  `legion.services.<name>` option; each Legion service's own feature file
  sets its own entry (node, ports, firewall, Volume, backup set), and
  `modules/hosts/legion/default.nix` derives per-node module imports,
  firewall openings, Volume `fileSystems`, and `backups.jobs` from it.
- `modules/<feature>.nix`, or `modules/<feature>/` when it has sibling
  files (secrets shard, Lua, JSON, script): one flake-parts module that
  implements the feature for every class it applies to. A secret shard sits
  beside its consumer as `secrets.yaml`; a second shard in the same
  directory is `secrets.<consumer>.yaml` (`netbird-server/secrets.proxy.yaml`).
- Features contribute to roles, not their own names: `nixos.modules.base` /
  `darwin.modules.base` (every host of the class), `nixos.modules.artemis`,
  `nixos.modules.legion`, and one kebab-case `nixos.modules.<service>` per
  Legion service. Hosts are `nixos.configurations.<host>.module` /
  `darwin.configurations.<host>.module` (`modules/configurations.nix`).
- `modules/packages/`: packages and wrapped programs.
- `dns/dnsconfig.js`: public DNS.
- `docs/runbooks/`: procedures that recur.
- `docs/topology/`: nix-topology diagrams rendered from the host
  configurations. Generated, not hand-edited: re-run `just topology` and
  commit the result when the fleet's hosts, networks, or services change.

## Operating the fleet

### Guardrails

- Never run `sudo` or `doas` yourself on any host. Give the operator the
  exact command. The operator's shell is fish on every machine: write fish
  syntax, and wrap POSIX one-liners run over SSH in `bash -c '...'`.
- Deploy, `clean-deploy`, `install`, `disko-format`, and any sops change
  need the user's explicit approval for that action and target. Approval
  can be conditional ("merge and deploy when CI is green").
- Do not print, decrypt, move, or re-key secrets unless the task asks for it.
- Do not change disk layouts, host networking, or deploy targets as
  incidental cleanup. Never run a command that destroys or formats a disk
  unless the user names the host.

### Access

- Legion: `node1.jeiang.dev`..`node4.jeiang.dev`. NetBird mesh names for
  these nodes carry collision suffixes, and mesh SSH from the Mac times out.
  `sudo` needs a password and a TTY (`ssh -t`).
- artemis: `artemis.jeiang.vpn`. A bare `artemis` resolves through the
  wildcard record and does not reach the host. `doas` is passwordless;
  deploy-rs depends on that. When NetBird is down, `legion-node1` reaches
  artemis at `10.100.0.2` over the `wg-backup` WireGuard tunnel.
- artemis has an EDID dummy plug on `HDMI-A-1`. The motherboard does not
  POST without a powered display, so the plug must stay in.

### Deploying

- Deploy only after the pull request is merged and CI has pushed the
  closures to garret, so targets substitute instead of building.
- zakkart activates itself: `just nh darwin switch`. Give the operator that
  command, not `darwin-rebuild`.
- From the Mac: `just deploy <host> --skip-checks --remote-build`. The fleet
  form is `just deploy-legion --remote-build`: it passes `--skip-checks`
  itself, so do not pass it again. Check each node after its deploy; `just
  deploy-legion` does not replace that.
- deploy-rs magic rollback protects only a live switch. On artemis,
  removing a service that owns an impermanence bind mount cannot switch
  live: deploy with `--boot`, then reboot. Kernel and initrd changes also
  need `--boot` and a reboot.
- artemis boots a new generation with 2 tries. `boot-health.service`
  blesses it once sshd is active and NetBird reports its management server
  connected, within 5 minutes; otherwise the host reboots, and the second
  failure falls back to the previous generation. After a reboot, confirm
  `readlink /run/current-system` is the deployed closure. A redeploy of the
  same closure reuses the spent entry: to retry it, the operator renames
  `/boot/loader/entries/nixos-<hash>+0-2.conf` to `nixos-<hash>+2.conf`.

### artemis persistence

- The root subvolume is rolled back to empty on every boot. Only
  `persistence.*` paths survive, and impermanence never copies existing
  data into `/persist`.
- Before deploying any change to `persistence.*` (an added entry, or an
  entry moved between system, data, and cache), run
  `just migrate-persist <checkout>` on artemis as root from a checkout of
  the new revision, then deploy with `--boot` and reboot. After the reboot
  the old data is only in `old_roots`.
- Persisting a path does not back it up. A backup set is an explicit
  allowlist, and every path in it must also be a `persistence.*` path.
  artemis backs up its allowlist (`modules/backups/default.nix`) from a
  read-only btrfs snapshot of `/persist`, so the paths in its snapshots
  carry a `/persist/.backup-snapshot` prefix. A btrfs snapshot is not
  recursive: a backup path that is, or contains, a nested subvolume would
  back up as an empty directory.

### Secrets

- sops-nix on every host, zakkart included. One shard per consuming module,
  encrypted to the admin key and exactly the hosts that run the consumer. A
  host's recipient is its ed25519 host key through `ssh-to-age`. `.sops.yaml`
  has one rule per shard, anchored on the full path. There is no `defaultSopsFile`, so a
  secret without a shard fails evaluation.
- `just sops-edit` adds or changes values. `just sops-updatekeys` is needed
  only after a recipient change in `.sops.yaml`.
- A rotated secret reaches a running process only through that secret's
  `restartUnits`.
- `modules/sops/secrets.admin.yaml` is the admin's own stash. No module
  consumes it.

## Decisions that constrain changes

- The deploy user is a Nix trusted user, so it is root-equivalent. Its sudo
  rules are for audit, not containment. Removing that trust needs a
  signed-closure delivery design.
- Hetzner servers, Volumes, and Cloud Firewalls are provisioned outside the
  flake. A Volume is for state that cannot suffer loss if the server fails.
  A stateful Legion service that keeps such state uses a Volume and
  `mountGuard`, so a missing Volume never initializes fresh state on the
  root disk. State that can tolerate losing the interval since its last
  backup instead lives on the root disk with a `backupSet` restic job as
  its whole durability story; atuin on `legion-node4` is the first such
  service. Exactly one node owns each stateful service; moving it is an
  explicit Volume (or backup) and state migration, not a placement edit
  alone.
- Legion host firewalls are on. A `legion.services.<name>` entry's
  `scope = "private"` is documentation: `enp7s0` and the NetBird interface
  are trusted interfaces. A public opening also needs a rule in `legion`,
  the one Hetzner Cloud Firewall all four nodes share. It is attached by
  server ID, so a new node must be attached to it explicitly. Public ICMP
  stays blocked there; the operator opens it by hand when needed.
- `netbird-proxy` on `legion-node2` is public and terminates its own TLS
  (DNS-01 wildcard for `proxy.jeiang.dev`). CrowdSec IP reputation and an
  nftables bouncer protect it with decisions from the LAPI on
  `legion-node1`. The host opens TCP/UDP 40000-45000 for ad hoc services,
  and `legion` allows that range on every node, so a port in it is public
  on any node whose host firewall opens it.
- Blackbox probes target private backend addresses, never public URLs.
  Probes through the edge would get the prober banned by CrowdSec.
- Anubis gates only the static content sites. Never put it in front of a
  machine client (substituters, OIDC, NetBird gRPC, Actual sync,
  Prometheus). Its challenge store stays in memory.
- Stateless by choice: Gatus stores results in memory, and tinyauth's
  database holds only sessions.
- The H@H backup keeps the full cache: a restore costs less than earning
  back H@H trust and quota.
- artemis and Legion back up to separate S4 buckets with separate keys, and
  one repository password covers all of Legion. A host that owns no backup
  job is therefore not a recipient of a backups shard, and adding one back
  means rotating the key it could read.
- `cache.jeiang.dev` and `cache-push.jeiang.dev` stay DNS-only in
  Cloudflare. Cloudflare rejects push bodies over 100 MB, and a proxied
  puller gets shared-PoP bans. The signing key `cache.jeiang.dev-1` is named
  for the function, not the implementation.
- garret accepts pushes from GitHub Actions OIDC tokens for
  `refs/heads/main` of any repository owned by `jeiang`, and from a Pocket ID
  client. There is no per-repository check.
- `dns/dnsconfig.js` is the source of truth for the Cloudflare zones. CI
  applies it on merge with full purge; only `_acme-challenge` TXT records
  are ignored. A dashboard edit is for emergencies and must be copied back
  into the file. `noelejoshua.com` is in its owner's Cloudflare account.
- Determinate Nix owns the Nix installation on every host. On zakkart
  `nix.enable = false`; settings go through `determinateNix.customSettings`,
  which does not merge, so use `extra-*` keys.
- zakkart applications come from nixpkgs first. Homebrew casks (pinned
  taps, `cleanup = "zap"`) are for applications with no working darwin
  package or that must manage themselves (`netbird-ui` owns its daemon).
  Bitwarden, Yubico Authenticator, and Wipr 2 come from the Mac App Store.
- zakkart preferences that nix-darwin cannot express are scripted in
  activation with values observed on macOS 26. Steps that depend on user
  consent warn instead of failing.
- artemis runs a CachyOS full-LTO kernel for Zen 4 with BORE, built from
  source on purpose. The Raphael iGPU display function (`1002:164e`) is
  bound to pci-stub because its PSP fails amdgpu initialization on some
  boots; the firmware still uses it, so BIOS setup keeps working.
- artemis's btrfs root is RAID0 across three NVMe drives for throughput. The
  loss of one drive loses the pool.
- bees runs only from 03:00 to 09:00, because it stalls game I/O.
- Pocket ID keeps its SMTP settings in its database. Enter them again in the
  admin UI after a fresh install.
- NetBird peer IPs in `modules/netbird-peers.nix` change when a peer
  enrolls again.
- Agent skills, subagents, and instructions come from the pinned
  `agent-skills` flake, installed by hjem on artemis and zakkart. The
  `<harness>-personal` package holds the tree, and `lib.entries` names its
  entries, so nothing here parses that repository's layout. Skills and
  subagents are one symlink per entry, because both clients keep their own
  entries in those directories, and the names must come from `lib.entries`:
  reading them from the built package is import-from-derivation, which breaks
  evaluating one host from the other's system. `CLAUDE.md` and `AGENTS.md` are
  copies: Claude Code ignores a symlinked user `CLAUDE.md`. Changes land by
  bumping the input, not by editing the installed files.
- `modules/mcp/` renders one MCP server list, and only omp gets it as a file
  (`~/.omp/agent/mcp.json`). Claude Code keeps user-scope servers in
  `~/.claude.json` and Codex in `~/.codex/config.toml`, both of which those
  clients rewrite, so the operator registers the servers there by hand.
  Grafana is reached over the mesh, never through the edge.
- The agent CLIs come from the `llm-agents` input, which tracks upstream
  releases faster than nixpkgs. Its `nixpkgs` deliberately does not follow
  ours: `cache.numtide.com` only serves builds made against its own pin, so
  a `follows` would rebuild every agent from source.
- `claude` on artemis and zakkart is the wrapped package from
  `modules/claude-code/`. The wrapper exports `TYPESAFE_API_KEY` from the
  sops secret at launch, so the key is never in the store and the desktop
  app does not get it. The token only reaches the TypeSafe API; rotate it
  with `just sops-edit` and a switch.
- hermes-ops tiers on Legion: tier 0 is `journalctl`/read access via
  `systemd-journal` group membership; tier 1 is the mechanical `systemctl
  start`/`restart` allowlist; tier 2 is `stop`, `start`/`restart` of a
  non-tier-1 unit, and `systemctl reboot`, and runs only after a Telegram
  approval; tier 3 is never granted. `flake.lib.hermesOpsCommands`
  (`modules/hermes-ops.nix`) is the one definition of both tiers: that
  module renders each entry into a Legion sudoers rule, and the
  plugin in `modules/hermes/tier2` matches Hermes' terminal command against
  the same text, escalating a tier-2 match through the agent's own approval
  gate and refusing everything else that reaches a node through sudo. A sudo
  rule alone never authorizes a tier-2 command; deny, timeout and every
  unattended surface mean it did not run. Moving a unit between tiers is a
  redeploy of the node and of artemis.
- The Hermes model server (`modules/llm-server`) runs Qwen3.6-35B-A3B
  (UD-Q4_K_XL) with the MoE experts of the first layers on the CPU, because
  the weights exceed the dGPU, and with thinking disabled.
- The weights live under the persisted cache directory and never in the Nix
  store; `llm-server-fetch.service` downloads and checksums them onto disk.
- `just llm-stop` and `just llm-start` are the manual counterpart of the
  gamemode hooks that free the dGPU for a game.
- Jev (TypeSafe System One) judgments run in code in front of Hermes --
  systemd services and a shell hook (`modules/hermes/jev/`) -- never as a
  tool the agent itself chooses.

## CI

- `ci.yml` evaluates `checks.x86_64-linux`, builds each check in a matrix
  job, and pushes the results to garret on `main`. zakkart builds on a macOS
  runner. `all-checks` is the only required status.
- Only a `main` run pushes to garret. A change that rebuilds the artemis
  kernel must therefore be built on artemis and pushed to garret before the
  branch is pushed, or every PR run compiles the full-LTO kernel on a shared
  runner against its job time limit. deploy-rs installs
  `deploy.nodes.<host>.profiles.system.path`, not the toplevel, so push that
  too: it carries `activate-rs`, and when a rustc bump drops it from the
  cache, `--remote-build` makes each target compile deploy-rs itself.
- `dns.yml` previews DNS changes on pull requests, pushes them on merge, and
  runs a weekly drift check.
