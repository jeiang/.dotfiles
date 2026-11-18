# AGENTS.md

`cornn-flaek` is a flake-parts + import-tree flake. `main` is what every
machine must run.

| Host | Kind | Role |
| --- | --- | --- |
| `artemis` | NixOS | Headless gaming and streaming box at home. Impermanent btrfs root. Sunshine/Moonlight and hypr-rdp over NetBird; atrium, media, Factorio, and Minecraft. Games enter through ricklent. |
| `zakkart` | nix-darwin | The operator's MacBook. |
| `alda` | NixOS | Legion server, Hetzner Cloud. Caddy edge (also fronts atrium on artemis). |
| `vida` | NixOS | Legion server, Hetzner Cloud. NetBird server/relay/proxy, Pocket ID, Blocky. |
| `zantark` | NixOS | Legion server, Hetzner Cloud. Monitoring, gatus, atuin, and CrowdSec agent/firewall bouncer. |
| `peria` | NixOS | Legion server, Hetzner Cloud. garret with its own Caddy and CrowdSec firewall bouncer, and hath. |
| `ricklent` | NixOS | Legion server, Linode VPS in Atlanta (not Hetzner). Game ingress to artemis, second NetBird reverse proxy replica, qBittorrent WireGuard exit, secondary Blocky, independent Gatus, and CrowdSec agent/firewall bouncer. No Volumes or provider firewall. |

Legion is the fleet's servers, whatever the provider: four run on Hetzner
Cloud, `ricklent` on Linode. `legionNodes.<name>.provider` (`hetzner` or
`linode`) selects the provider-specific parts.

Backwards compatibility matters only for rollback. Flag a change that would
break a rollback to the previous generation; otherwise do not keep old
behavior for its own sake.

## Workflow

- Never commit to `main`. Use a branch and a pull request. `main` is
  protected and requires signed commits. Merge with
  `gh pr merge --auto --merge` after CI passes. Wait for CI with
  `gh pr checks <n> --watch --fail-fast --interval 30` as a background job,
  then confirm `gh pr view <n> --json state,mergedAt`. Do not add
  `--required`: `all-checks` needs every other job, so it is not reported
  until they finish and the command exits at once.
- Use Conventional Commits.
- Repository tools come from the devshell: `direnv` loads `.envrc`, or run
  `nix develop -c <cmd>`.
- Validate with `just fmt` and `just check`. For one host, compare
  `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
  (or `.#darwinConfigurations.zakkart...`) before and after the change. Do
  not use `nix flake show`: it enumerates outputs that are invalid on the
  current system.
- Everything evaluates in pure mode, CI included. Never add `--impure`.
- In a new git worktree, enter the devshell (or copy the gitignored
  `.pre-commit-config.yaml` symlink from the main checkout) before the
  first commit; the shell hook installs the git hooks.
- Before opening a pull request, and after any flake input bump, run
  `just prepush`. It builds on artemis every Linux host toplevel and deploy
  profile path that differs from `origin/main`, builds the zakkart toplevel
  here if it differs, and pushes the closures to garret. Make no PR until it
  finishes: a PR run never pushes to garret, so whatever CI must compile
  (the full-LTO artemis kernel, deploy-rs after a rustc bump) builds on a
  shared runner against its job time limit. A slow build that no host
  closure contains is built the same way with
  `nix build --eval-store auto --store ssh-ng://artemis.jeiang.vpn` and
  pushed from artemis with `garret push`.
- A command that runs more than once becomes a `justfile` recipe.
  `just --list` is the recipe index.

## Code rules

- The code describes the system; it does not carry prose. Write a comment
  only for a workaround (what is broken and why), for one line of context
  the code cannot express, or as a one- or two-line purpose note on an
  obscure script. Never write history, measurements, rejected alternatives,
  or "matches X elsewhere" notes. Git history is the archive. A decision
  that constrains future changes goes in this file when it guards the whole
  fleet, otherwise in its topic file under `docs/decisions/`.
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
  sets its own entry (node, ports, public ports, Volume, backup set, DNS-only
  hostnames), and `modules/hosts/legion/default.nix` derives per-node module
  imports, firewall openings, monitored units, and `backups.jobs` from it.
  Each node also imports the module of its provider
  (`legionNodes.<name>.provider`): `nixos.modules.hetzner`
  (`modules/hosts/legion/hetzner.nix`: disko, Volume `fileSystems`, the
  private NIC, the WAN gateways) or `nixos.modules.linode`
  (`modules/hosts/ricklent/`: BIOS GRUB disk, DHCP/IPv6 network, resource
  settings).
- `modules/<feature>.nix`, or `modules/<feature>/` when it has sibling
  files (secrets shard, Lua, JSON, script): one flake-parts module that
  implements the feature for every class it applies to. A secret shard sits
  beside its consumer as `secrets.yaml`; a second shard in the same
  directory is `secrets.<consumer>.yaml` (`netbird-server/secrets.proxy.yaml`).
- Features contribute to roles, not their own names: `nixos.modules.base` /
  `darwin.modules.base` (every host of the class), `shared.modules.base`
  (every NixOS and darwin host) and `shared.modules.workstation` (artemis and
  zakkart) for config valid on both classes, `nixos.modules.artemis`,
  `nixos.modules.legion`, and one kebab-case `nixos.modules.<service>` per
  Legion service. Hosts are `nixos.configurations.<host>.module` /
  `darwin.configurations.<host>.module` (`modules/configurations.nix`).
- A value another module needs is a `flake.lib` name defined by the module
  that owns it (`netbirdDomain`, `pocketIdUrl`, `cacheHostname`,
  `deployUser`, ...). A Legion service's address comes from
  `self.lib.serviceAddress <fromNode> <service>`, and its NetBird mesh IP
  from `self.lib.serviceMeshAddress <service>`; never type a node name for
  where a service runs.
- Every NixOS host's node exporter reports only `monitoredUnits`; each
  module adds the units it owns (Legion services through `units`).
- `modules/packages/`: packages and wrapped programs. A package that only
  builds on Linux goes in `perSystem.linuxPackages`, one that only builds on
  darwin in `perSystem.darwinPackages`.
- `dns/dnsconfig.js`: public DNS.
- `docs/decisions/`: decisions that constrain changes, one file per topic,
  indexed under "Decisions that constrain changes".
- `docs/runbooks/`: procedures that recur.
- `docs/topology/`: nix-topology diagrams rendered from the host
  configurations. Generated, not hand-edited: re-run `just topology` and
  commit the result when the fleet's hosts, networks, or services change.

## Operating the fleet

### Guardrails

- Never run `sudo` yourself, and never reboot a host, unless the
  user explicitly permits it for the current task; that permission covers
  only that task. Otherwise give the operator the exact command. The
  operator's shell is fish on every machine: write fish syntax, and wrap
  POSIX one-liners run over SSH in `bash -c '...'`.
- Deploy, `clean-deploy`, `install`, `disko-format`, and any sops change
  need the user's explicit approval for that action and target. Approval
  can be conditional ("merge and deploy when CI is green").
- Do not print, decrypt, move, or re-key secrets unless the task asks for it.
- Do not change disk layouts, host networking, or deploy targets as
  incidental cleanup. Never run a command that destroys or formats a disk
  unless the user names the host.

### Access

- Legion: `<name>.svr.jeiang.dev` (`alda.svr.jeiang.dev`, ...). NetBird mesh names for
  these nodes carry collision suffixes, and mesh SSH from the Mac times out.
  `sudo` asks for no password inside an SSH session, which only the
  operator's key can open; a console session needs the password
  (`modules/openssh.nix`).
- artemis: `artemis.jeiang.vpn`. A bare `artemis` resolves through the
  wildcard record and does not reach the host. `sudo` follows the same rule
  as on Legion. deploy-rs logs in as the `deploy` user on every NixOS
  host. When NetBird is down, `alda` reaches artemis at `10.100.0.2` over
  the `wg-backup` WireGuard tunnel.
- artemis has an EDID dummy plug on `HDMI-A-1`. The motherboard does not
  POST without a powered display, so the plug must stay in.

### Deploying, persistence, and secrets

Read the runbook before you act:

- A deploy, a reboot, or a question about auto-upgrade:
  [`docs/runbooks/deploy.md`](docs/runbooks/deploy.md). Deploy only after
  the pull request is merged and CI has pushed the closures to garret.
- A change to artemis `persistence.*` or to a backup set: the persistence
  section of the same runbook. Such a change needs
  `just migrate-persist` and a `--boot` deploy.
- A sops secret, shard, or recipient:
  [`docs/runbooks/secrets.md`](docs/runbooks/secrets.md). Never edit
  `.sops.yaml`; it is generated.

## Decisions that constrain changes

- The deploy user is a Nix trusted user on every NixOS host, so it is
  root-equivalent. Its sudo rules are for audit, not containment. Removing
  that trust needs a signed-closure delivery design.
- A merge to `main` reaches every NixOS host without the operator's SSH
  key, so the protection of `main` (signed commits, a pull request,
  `all-checks`) is what guards root on the fleet. The commit status only
  tells a host when to look: the system comes from the host's own
  evaluation of `main` and from paths garret signed. The health check
  cannot see broken inbound access, so a system on which sshd runs but
  refuses the operator stays.
- `sudo` skips the password only for a caller inside an sshd logind
  session of the same user; sshd accepts only keys, so that session proves
  the operator's key. Any other session (console, desktop, Rex) asks for the
  password, and sudo then remembers the authentication for two hours for
  every session of that user on the host (`timestamp_type=global`). gamemode
  stops and starts `gaming.pauseUnits` through a polkit rule, not elevation.
- Long builds run on artemis, not on zakkart and not on a CI runner:
  `nix build --eval-store auto --store ssh-ng://artemis.jeiang.vpn
  <installable>` evaluates here and builds there, over the operator's own ssh
  agent. Artemis is not a `builders` entry on zakkart: the Nix daemon
  connects as root, so it would need a root-readable private key for a
  trusted user on artemis, which makes the Mac's root root-equivalent there
  without the operator's key gate.

Read the topic file before changing anything it covers:

|Topic|File|
|---|---|
|Hetzner and Linode provisioning, Volumes, private network, firewalls, NetBird mesh and management, CrowdSec, enrollment|[`docs/decisions/legion.md`](docs/decisions/legion.md)|
|Monitoring, Gatus, journald, Anubis, H@H, garret and the cache, portfolio, website, DNS, Pocket ID|[`docs/decisions/services.md`](docs/decisions/services.md)|
|Restic repositories and the artemis copy|[`docs/decisions/backups.md`](docs/decisions/backups.md)|
|artemis kernel and storage, bees, Minecraft, media, qBittorrent, atrium|[`docs/decisions/artemis.md`](docs/decisions/artemis.md)|
|Determinate Nix, zakkart applications and preferences, agent skills, MCP, agent CLIs|[`docs/decisions/workstations.md`](docs/decisions/workstations.md)|

## CI

- `ci.yml` evaluates `checks.x86_64-linux` and builds each check in a matrix
  job. On `main`, `.ci/garret.sh` pushes each path to garret as it is built,
  and drains the rest even when the build fails; a garret failure never
  fails the job. zakkart builds on a macOS runner only when garret does not
  already serve its system and, on a PR, its toplevel derivation differs
  from the base. `all-checks` is the only
  required status. On a pull request, a leg whose output garret already
  serves builds nothing. On `main`, each `toplevel-<host>` leg then sets the
  commit status `system/<host>` to the system's store path, which that
  host's auto-upgrade reads.
- Only a `main` run pushes to garret, so a PR run cannot substitute a
  rebuilt artemis kernel or any other long source build and would compile it
  on a shared runner against its job time limit (see Workflow for
  `just prepush`).
  deploy-rs installs `deploy.nodes.<host>.profiles.system.path`, not the
  toplevel, so that path is pushed too: it carries `activate-rs`, and when a
  rustc bump drops it from the cache, `--remote-build` makes each target
  compile deploy-rs itself.
- `dns.yml` previews DNS changes on pull requests, pushes them on merge, and
  runs a weekly drift check.
- `hcloud.yml` is read-only and advisory (not part of `all-checks`): it runs
  `modules/hcloud-drift/check.sh` (what `just hcloud-drift` also runs) as a
  non-blocking preview on pull requests, and fails on push to `main`, weekly
  schedule, and `workflow_dispatch`.
- `topology.yml` re-renders `docs/topology/` weekly and on
  `workflow_dispatch`, and opens a pull request when the diagrams changed.
