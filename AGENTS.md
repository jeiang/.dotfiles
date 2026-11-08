# AGENTS.md

`cornn-flaek` is a flake-parts + import-tree flake. `main` is what every
machine must run.

| Host | Kind | Role |
| --- | --- | --- |
| `artemis` | NixOS | Headless gaming and streaming box at home. Impermanent btrfs root. Sunshine/Moonlight and hypr-rdp over NetBird; atrium, media, Factorio, and Minecraft. Games enter through ricklent. |
| `zakkart` | nix-darwin | The operator's MacBook. |
| `alda` | NixOS | Legion server, Hetzner Cloud. Caddy edge (also fronts atrium on artemis). |
| `vida` | NixOS | Legion server, Hetzner Cloud. NetBird server/relay/proxy, Pocket ID, Blocky. |
| `zantark` | NixOS | Legion server, Hetzner Cloud. Monitoring, ntfy, gatus, atuin, and CrowdSec agent/firewall bouncer. |
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
  (the full-LTO artemis kernel, a source-built package such as the omp
  override, deploy-rs after a rustc bump) builds on a shared runner against
  its job time limit. A slow build that no host closure contains is built the
  same way with `nix build --eval-store auto --store ssh-ng://artemis.jeiang.vpn`
  and pushed from artemis with `garret push`.
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
- `docs/runbooks/`: procedures that recur.
- `docs/topology/`: nix-topology diagrams rendered from the host
  configurations. Generated, not hand-edited: re-run `just topology` and
  commit the result when the fleet's hosts, networks, or services change.

## Operating the fleet

### Guardrails

- Never run `sudo` or `doas` yourself, and never reboot a host, unless the
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
  wildcard record and does not reach the host. `doas` follows the same rule
  as Legion's `sudo`. deploy-rs logs in as the `deploy` user on every NixOS
  host. When NetBird is down, `alda` reaches artemis at `10.100.0.2` over
  the `wg-backup` WireGuard tunnel.
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
  allowlist, and every path in it must also be a `persistence.*` path: each
  module adds its own paths, excludes and snapshot-stop units to
  `backups.persist` next to its persistence entries. artemis backs them up
  from a read-only btrfs snapshot of `/persist`, so the paths in its snapshots
  carry a `/persist/.backup-snapshot` prefix. A btrfs snapshot is not
  recursive: a backup path that is, or contains, a nested subvolume would
  back up as an empty directory.

### Secrets

- sops-nix on every host, zakkart included. One shard per consuming module,
  encrypted to the admin key and exactly the hosts that run the consumer. A
  host's recipient is its ed25519 host key through `ssh-to-age`, declared in
  `modules/sops/default.nix`. There is no `defaultSopsFile`, so a secret
  without a shard fails evaluation.
- `.sops.yaml` is generated from the `sops.secrets` each host declares; do
  not edit it. To add a shard, declare the secret in its consumer, run
  `just sops-config`, then `just sops-edit <path>`; run `just
  sops-updatekeys` after a recipient change. The `sops-config` check fails
  while the committed file is stale. Shard paths must match
  `lib.sopsShardRegex`.
- A rotated secret reaches a running process only through that secret's
  `restartUnits`.
- On NixOS, `sops-install-secrets.service` (`useSystemdActivation`)
  installs the secrets before `sysinit.target`, not an activation script,
  because NixOS is removing restarts requested from activation scripts. It
  requests `restartUnits` with `systemctl --no-block try-restart`, outside
  switch-to-configuration's own jobs: a consumer that has failed when the
  switch ends still fails the deploy, but one that fails later does not,
  and its restart is not listed in the deploy output. A consumer that starts before
  `sysinit.target` or reads a secret in an activation script needs its own
  ordering or a start-time copy (alda's `systemd-networkd`). Secrets with
  `neededForUsers` still install from an activation script.
- `modules/sops/secrets.admin.yaml` is the admin's own stash. No module
  consumes it.

## Decisions that constrain changes

- The deploy user is a Nix trusted user on every NixOS host, so it is
  root-equivalent. Its elevation rules (sudo on Legion, doas on artemis) are
  for audit, not containment. Removing that trust needs a signed-closure
  delivery design.
- `sudo`/`doas` skip the password only for a caller inside an sshd logind
  session of the same user; sshd accepts only keys, so that session proves
  the operator's key. gamemode stops and starts `gaming.pauseUnits` through
  a polkit rule, not elevation.
- Hetzner servers, Volumes, and Cloud Firewalls are provisioned outside the
  flake, and are Hetzner-only. A Volume is for state that cannot suffer loss
  if the server fails. A stateful Legion service that keeps such state uses
  a Volume and `mountGuard`, so a missing Volume never initializes fresh
  state on the root disk. State that can tolerate losing the interval since
  its last backup instead lives on the root disk with a `backupSet` restic
  job as its whole durability story; atuin on `zantark` is one such
  service. ricklent has no Volumes, so a stateful service there must use
  that root-disk-plus-restic pattern (a Volume on a non-Hetzner node fails
  evaluation). Exactly one node owns each stateful service; moving it is an
  explicit Volume (or backup) and state migration, not a placement edit
  alone. Legion `fileSystems` entries for a Volume mount by ext4 label, not
  by `hcloudVolumeId`: a new Volume must be formatted with its
  `legion.services.<name>` key as that label (at most 16 bytes) before the
  deploy that mounts it. A Hetzner server disk is addressed as
  `self.lib.hetznerServerDisk` (LUN 0 by path), never `/dev/sdX`: an
  attached Volume can take `sda`.
- The Hetzner private network (`172.16.0.0/12`, `enp7s0`) exists only on
  Hetzner nodes, and no NetBird route reaches it from the mesh. Hetzner
  nodes address each other by `privateIPv4`; every pair involving ricklent
  uses the target's
  mesh IP from `modules/netbird-peers.nix`, through
  `self.lib.legionAddress <from> <to>` (null until the target has a peer
  entry, and then dropped from scrape targets). ricklent's peer entry is
  added after it first enrolls, and until then its journald upload,
  CrowdSec agent, and scrape do not connect. Every connection between Legion
  machines that crosses the mesh is a `meshFlows` entry in
  `modules/netbird-management`, whose ports the `Legion Mesh` access
  policies allow; a new one needs an entry there. NetBird DNS clients use
  Blocky on vida and ricklent at their mesh IPs (port 553, TCP and UDP).
- Legion host firewalls are on. `legion.services.<name>.publicPorts` and
  `publicPortRanges` are the internet openings; `enp7s0` (Hetzner nodes) and the
  NetBird interface are trusted interfaces. On a Hetzner node a public
  opening also needs a rule in `legion`, the one Hetzner Cloud Firewall the
  four Hetzner nodes share. It is attached by
  server ID, so a new Hetzner node must be attached to it explicitly. Public
  ICMP stays blocked there; the operator opens it by hand when needed.
  `just hcloud-drift` (`modules/hcloud-drift/`) proves live state matches
  this for Hetzner nodes only: the expected rule set is the union of each
  Hetzner node's merged `networking.firewall`, not `legion.services` (a node
  can open a port through another module), and it excludes ICMP. ricklent's
  Linode Cloud Firewall is attached to its public interface and must allow
  the public TCP/UDP ports and ranges in its `networking.firewall`.
- ricklent's Linode boot profile uses Direct Disk with the distro, module,
  and devtmpfs helpers disabled. The flake partitions `/dev/sda` and
  installs BIOS GRUB; Direct Disk boots that installed bootloader.
- `netbird-proxy` (`modules/netbird-server/proxy.nix`) is one cluster,
  `proxy.jeiang.dev`, with a replica on `vida` and one on `ricklent`
  (`netbird-proxy-atl`). Management groups proxies by domain and sends
  every service to every replica; DNS lists both hosts for `proxy` and
  `*.proxy`, with no health check, so a down replica still gets about half
  of new connections until the client retries. Each replica binds public
  TCP 443, terminates its own TLS (DNS-01 wildcard per host) with no PROXY
  protocol, and has its own proxy token and CrowdSec bouncer key; the
  Cloudflare DNS token is the one shared shard in `modules/cloudflare`, which
  the edge also reads. CrowdSec IP reputation protects both with decisions from the LAPI
  on `alda`; vida also runs an nftables bouncer here. Each host opens
  TCP/UDP 40000-45000 for ad hoc services, and the Hetzner `legion`
  firewall allows that range, so a port in it is public on any Hetzner
  node whose host firewall opens it. There is no Atlanta relay; vida's
  relay serves every peer.
- ricklent and zantark each run a CrowdSec agent (sshd logs from the
  journal) and an nftables bouncer against the LAPI on `alda`
  (`modules/crowdsec/agent.nix`). Every LAPI credential is an entry in the
  `crowdsec.bouncers` registry, which alda registers; firewall bouncers are
  named `<node>-firewall`. A node's machine and bouncer credentials live in
  `modules/crowdsec/secrets.<node>.yaml`, readable only by alda and that
  node. alda reads its own sshd journal and runs an nftables bouncer
  registered against its local API, so sshd bans act on the host firewall,
  not only in Caddy.
- CrowdSec keeps its database and hub under `/var/lib/crowdsec/state` on
  every Legion node, not the nixpkgs default data directory. alda's local
  API credentials stay at `/etc/crowdsec/local_api_credentials.yaml`; the
  agents disable their local API and use their sops-rendered credentials.
- `modules/netbird-management/` declares the NetBird management state
  (groups, access policies, networks, DNS, setup key, users' groups, service
  users and tokens, account settings) with nb-nix (`github:jeiang/nb-nix`),
  which plans and applies it through the management API. Undeclared objects
  are deleted, except the groups Pocket ID once synced, which only the
  dashboard can delete. Users are matched by NetBird user ID, so no email
  address is in this public repository. Groups come from NetBird, not Pocket
  ID (`jwt_groups_enabled` is off); Pocket ID only decides who may sign in.
  `just netbird-plan` previews a change and `just netbird-apply` applies that
  plan with the nb-nix admin token in `modules/sops/secrets.admin.yaml`.
  `.github/workflows/netbird.yml` runs the plan weekly with an Auditor-role
  token (`NETBIRD_READ_TOKEN`) and fails on drift. nb-nix renews both tokens
  30 days before expiry when an apply runs; `docs/runbooks/netbird.md` has
  the procedures.
- Blackbox probes target private backend addresses, never public URLs.
  Probes through the edge would get the prober banned by CrowdSec.
- Anubis gates only the static content sites. Never put it in front of a
  machine client (substituters, OIDC, NetBird gRPC,
  Prometheus). Its challenge store stays in memory. Both Gatus instances
  resolve the content sites to the edge's private or mesh address, and the
  edge serves exactly those two sources without a challenge.
- Stateless by choice: Gatus stores results in memory, and tinyauth's
  database holds only sessions.
- `gatus-atl` on ricklent is the independent Atlanta watchdog: the same
  endpoints as zantark's `gatus`, alerting straight to Discord with
  `modules/gatus/secrets.yaml`, so it does not depend on zantark.
  zantark's `gatus` keeps alerting through Alertmanager.
- The H@H backup keeps the full cache: a restore costs less than earning
  back H@H trust and quota.
- Minecraft (`modules/minecraft.nix`, nix-minecraft Fabric with Geyser and
  Floodgate; Java on TCP 25565, Bedrock on TCP and UDP 19132) runs on
  `artemis`. `mc.jeiang.dev` enters through ricklent's IPv4/IPv6 stream
  proxy, never a public home firewall opening. The Java version follows what
  Geyser supports for the Bedrock clients in use. Geyser runs the NetherNet
  transport (Bedrock 26.60 drops RakNet) with built-in plain-HTTP
  signaling, so Bedrock players see a trust prompt on first join. The
  whitelist is declared for Java and Bedrock
  players alike (Bedrock as Floodgate `.`-prefixed names and XUID UUIDs),
  and each start rewrites `whitelist.json`, so runtime edits do not
  survive. Its state and Factorio's `/var/lib/factorio` are persisted and
  included in artemis's six-hourly `/persist` backup. Both games stop only
  while the read-only snapshot is created. Geyser advertises Atlanta's
  public addresses for ICE; the stream proxy does not preserve player IPs.
- artemis and Legion back up to separate S4 buckets with separate keys, and
  one repository password covers all of Legion. A host that owns no backup
  job is therefore not a recipient of a backups shard, and adding one back
  means rotating the key it could read.
- `cache.jeiang.dev` and `cache-push.jeiang.dev` stay DNS-only in
  Cloudflare. Cloudflare rejects push bodies over 100 MB, and a proxied
  puller gets shared-PoP bans. The signing key `cache.jeiang.dev-1` is named
  for the function, not the implementation.
- garret accepts pushes from a Pocket ID client and from GitHub Actions OIDC
  tokens of the workflows in its `job_workflow_refs` (`ci.yml` of
  `jeiang/.dotfiles`, `jeiang/garret`, `jeiang/atrium` and `jeiang/ripper`,
  ripper's `release.yml`, renpy_proj's `garret.yml`, `nix.yml` of
  `jeiang/erdtree` and `jeiang/cod4-decomp`), pinned by
  repository id, on `push` and `workflow_dispatch`, for `refs/heads/main`,
  `refs/heads/master` (erdtree's default branch) and
  `refs/tags/v*` (release tags, which are unprotected, so `ref_protected`
  stays unset). A new pushing repository or workflow needs its entries in
  `modules/garret/default.nix` first.
- garret's Puller runs as its own user with its own GetObject-only S3 key
  (`garret/puller-s3-*`); only the Pusher holds the bucket-write key. Its backup is an online
  `garret-admin backup` copy, so a backup never stops the cache.
- garret runs on `peria`; its own Caddy terminates `cache` and `cache-push`
  directly instead of alda's edge or Atlanta. Its SQLite index lives on
  the root disk with a six-hourly restic job, so a lost peria forgets pushes
  since the last snapshot. Both units skip their start while the index is
  missing: the Pusher would create an empty one, and its startup orphan
  sweep would then delete every bucket object older than 24 hours. This
  Caddy has no bouncer module or AppSec; peria's host nftables bouncer uses
  alda's LAPI with its key in `modules/crowdsec/secrets.peria.yaml`.
- The portfolio on `vida` runs whatever upstream `joshua-noel/portfolio`
  main builds: `portfolio-update` builds it as the `portfolio` user at
  00:00 UTC (and 2 minutes after activation) into
  `/var/lib/portfolio-update/current`, the GC root, and restarts the
  service when the path changes. Its owner's pushes go live without review.
  The `portfolio` flake input supplies only the NixOS module and the
  fallback package used until a first build exists; bump it when the
  module changes.
- The website on alda's edge follows the same pattern as the portfolio:
  `website-update` builds `github:jeiang/website` as the `caddy` user
  nightly (and 2 minutes after activation) into
  `/var/lib/website-update/current`, the GC root Caddy and Anubis read
  per request, so a new build needs no restart. `website-fallback` holds
  the root at the pinned `website` input until a first build exists; that
  input is only the fallback.
- `dns/dnsconfig.js` is the source of truth for the Cloudflare zones. CI
  applies it on merge with full purge; only `_acme-challenge` TXT records
  are ignored. The DNS-only A/AAAA records of Legion services come from each
  `legion.services.<name>.publicHostnames` through `dns/nodes.json`, which
  `just dns-nodes` regenerates (the `legion-nodes-json` check fails while it
  is stale); apex, wildcard, mail, CAA and TXT records stay hand-written. A
  dashboard edit is for emergencies and must be copied back into the file.
  `noelejoshua.com` is in its owner's Cloudflare account.
- Determinate Nix owns the Nix installation on every host. On zakkart
  `nix.enable = false`; settings go through `determinateNix.customSettings`,
  which does not merge, so use `extra-*` keys.
- zakkart applications come from nixpkgs first. Homebrew casks (pinned
  taps, `cleanup = "zap"`) are for applications with no working darwin
  package or that must manage themselves. NetBird is nix-managed
  (`modules/netbird-client.nix`): the daemon and the app are built from the
  same pinned source, because a cask app reinstalls its own daemon.
  Bitwarden, Yubico Authenticator, Wipr 2, and Xcode come from the Mac App
  Store.
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
- Pocket ID's application settings are declared in Nix under
  `UI_CONFIG_DISABLED`, which ignores the database's copy and locks the admin
  UI's settings page: an undeclared setting takes Pocket ID's default. The SMTP
  password reaches it from sops through `services.pocket-id.credentials`.
- Legion and artemis enroll with the non-ephemeral `Legion` setup key, which
  puts a new peer in the `Legion` group (artemis keeps it in its own
  `modules/hosts/artemis/secrets.yaml`). A peer enrolled by a user would
  inherit that user's groups. Preserve the addresses in
  `modules/netbird-peers.nix` when re-enrolling; nb-nix pins them.
- Agent skills, subagents, and instructions come from the pinned
  `agent-skills` flake, installed by hjem on artemis and zakkart. The
  `<harness>-personal` package holds the tree, and `lib.entries` names its
  entries, so nothing here parses that repository's layout. Skills and
  subagents are one symlink per entry, because both clients keep their own
  entries in those directories, and the names must come from `lib.entries`:
  reading them from the built package is import-from-derivation, which breaks
  evaluating one host from the other's system. `CLAUDE.md` and `AGENTS.md` are
  copies: Claude Code ignores a symlinked user `CLAUDE.md`. Changes land by
  bumping the input, not by editing the installed files. The one exception is
  REA's `reverse-engineer-anything` skill (`modules/rea.nix`), linked from the
  `rea` package because it describes that release's MCP tool catalog; a REA
  bump updates both.
- `modules/mcp/` renders one MCP server list, and only omp gets it as a file
  (`~/.omp/agent/mcp.json`). Claude Code keeps user-scope servers in
  `~/.claude.json` and Codex in `~/.codex/config.toml`, both of which those
  clients rewrite, so `just mcp-register` copies the list into them.
  Grafana is reached over the mesh, never through the edge. REA is not in
  that list, because its tool catalog would ride along in every session: a
  reverse-engineering project registers it itself, in `.omp/mcp.json`
  (`"rea": {"command": "rea", "args": ["mcp"]}`) and at project scope in
  Claude Code and Codex.
- The agent CLIs come from the `llm-agents` input, which tracks upstream
  releases faster than nixpkgs. Its `nixpkgs` deliberately does not follow
  ours: `cache.numtide.com` only serves builds made against its own pin, so
  a `follows` would rebuild every agent from source.
- The media tree on artemis (`modules/media.nix`) is one persisted
  directory, `/var/lib/media`, holding qBittorrent's downloads and the
  `movies/` and `tv/` library. It is not backed up, because it can be
  downloaded again. Two darkhttpd units serve the library read-only on 8084
  (movies) and 8085 (tv), mesh-only like the downloads listing on 8082.
- atrium's Media section owns filing and the EZTV watches (the former
  media-organizer is gone). `services.atrium.media` gives it the `media`
  group and `/var/lib/media`. `/media/file/*` is the one public path on the
  atrium vhost: Caddy skips tinyauth for it (still stripping `Remote-*`),
  and atrium serves the bytes only for a valid HMAC-signed, expiring link.
  The zakkart shim opens atrium's `/media/add` page instead of calling
  qBittorrent.
- qBittorrent runs in a network namespace on artemis whose only link besides
  loopback is a WireGuard interface to ricklent (`modules/qbittorrent/`), so
  with the tunnel down it has no route. ricklent masquerades its traffic and
  DNATs peer port 32881 to artemis's tunnel address. The namespace resolves
  through Quad9 over the tunnel, and the Web UI reaches the host through a
  socket proxy, so qBittorrent sees every Web UI client as loopback and
  whitelists it. The tunnel endpoint is ricklent's public IP, not its name:
  `wg` resolves inside the namespace, before any resolver is reachable.
- `atrium` is the code-owned service on artemis, built and documented in
  the `atrium` input (`jeiang/atrium`); its own `AGENTS.md` holds the mail,
  assistant, web auth and media decisions. `modules/atrium/` only wires
  `services.atrium` into artemis: `settings.mail.mail_mode = "live"`, the
  sops secrets (`atrium/env` for `ANTHROPIC_API_KEY`; one key per secret
  setting through `secretFiles`, the database key `atrium/db-key` included,
  and one app password per `mailAccounts` entry), the shared
  hostname and port (`flake.lib.atriumHostname`, `atriumWebPort`), the
  llama-server units (`self.lib.llamaServer`, models from
  `self.lib.llamaModels`, shared with cod4e-vision), persistence and backup.
  The database is encrypted with `atrium/db-key`; an archive opens only with
  the key it was made under, so the key also has an offline copy.
  cod4e-vision is stopped (`enabled = false` in `modules/cod4e-vision.nix`)
  so its servers do not compete with atrium's for the GPU; its persisted
  state directory and user stay.
  Bumping the input is how a code change reaches artemis.
- The public listener (`atrium-web`, `--auth proxy --auth oidc`) is reached
  through alda's Caddy at `atrium.jeiang.dev` behind tinyauth (Pocket ID group
  `atrium_access`). atrium trusts `Remote-Groups` before an OIDC session, so
  the edge must keep deleting the client's `Remote-*` headers before
  `forward_auth` copies tinyauth's in. Its port is open to every NetBird peer, because artemis
  trusts the NetBird interface; the NetBird ACLs, which admit only the
  operator's machines and the fleet, are the boundary. `atrium-web-local`
  (`--auth local`) listens on loopback only for emergency access over an SSH
  tunnel. Never open either port on another interface.
- atrium's model weights (Qwen3.5-9B chat, EmbeddingGemma 2) and the raw
  message cache live in `/var/lib/atrium/cache`, never in the Nix store. The
  directory is excluded from the artemis restic job. `atrium-backup` writes a
  daily `atrium backup` archive to `/var/lib/atrium/backups`, which the restic
  job carries; the module never prunes those archives. The directory is
  persisted, so it needs no `persistence.*` entry of its own.
- Long builds run on artemis, not on zakkart and not on a CI runner:
  `nix build --eval-store auto --store ssh-ng://artemis.jeiang.vpn
  <installable>` evaluates here and builds there, over the operator's own ssh
  agent. Artemis is not a `builders` entry on zakkart: the Nix daemon
  connects as root, so it would need a root-readable private key for a
  trusted user on artemis, which makes the Mac's root root-equivalent there
  without the operator's key gate.

## CI

- `ci.yml` evaluates `checks.x86_64-linux` and builds each check in a matrix
  job. On `main`, `.ci/garret.sh` pushes each path to garret as it is built,
  and drains the rest even when the build fails; a garret failure never
  fails the job. zakkart builds on a macOS runner, on a PR only when its
  toplevel derivation differs from the base. `all-checks` is the only
  required status.
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
