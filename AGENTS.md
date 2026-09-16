# AGENTS.md

`cornn-flaek` is a flake-parts + import-tree flake. `main` is what every
machine must run.

| Host | Kind | Role |
| --- | --- | --- |
| `artemis` | NixOS | Headless gaming and streaming box at home. Impermanent btrfs root. Reached over NetBird with Sunshine/Moonlight and hypr-rdp. |
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
  host secrets. Legion placement is data in
  `modules/hosts/legion/_service-inventory.nix`; files with a `_` prefix are
  not imported by import-tree.
- `modules/nixos/`, `modules/darwin/`: feature modules. A secret shard sits
  beside its consumer as `secrets.yaml`.
- `modules/packages/`: packages and wrapped programs.
- `dns/dnsconfig.js`: public DNS.
- `docs/runbooks/`: procedures that recur.

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
- From the Mac: `just deploy <host> --skip-checks --remote-build`. Check
  each node after its deploy; `just deploy-legion` does not replace that.
- deploy-rs magic rollback protects only a live switch. On artemis,
  removing a service that owns an impermanence bind mount cannot switch
  live: deploy with `--boot`, then reboot. Kernel and initrd changes also
  need `--boot` and a reboot.

### artemis persistence

- The root subvolume is rolled back to empty on every boot. Only
  `persistence.*` paths survive, and impermanence never copies existing
  data into `/persist`.
- Before deploying a change that adds a `persistence.*` entry, run
  `just migrate-persist <checkout>` on artemis as root from a checkout of
  the new revision, then deploy, then reboot.
- A persisted path is not backed up. A backup set is an explicit
  allowlist.

### Secrets

- sops-nix. One shard per consuming module, encrypted to the admin key and
  exactly the hosts that run the consumer. `.sops.yaml` has one rule per
  shard, anchored on the full path. There is no `defaultSopsFile`, so a
  secret without a shard fails evaluation.
- `just sops-edit` adds or changes values. `just sops-updatekeys` is needed
  only after a recipient change in `.sops.yaml`.
- A rotated secret reaches a running process only through that secret's
  `restartUnits`.
- `modules/nixos/sops/secrets.admin.yaml` is the admin's own stash. No
  module consumes it.

## Decisions that constrain changes

- The deploy user is a Nix trusted user, so it is root-equivalent. Its sudo
  rules are for audit, not containment. Removing that trust needs a
  signed-closure delivery design.
- Hetzner servers, Volumes, and Cloud Firewalls are provisioned outside the
  flake. A stateful Legion service keeps its state on a Volume and uses
  `mountGuard`, so a missing Volume never initializes fresh state on the
  root disk.
- Legion host firewalls are on. The inventory's `scope = "private"` is
  documentation: `enp7s0` and the NetBird interface are trusted interfaces.
  A public opening also needs its own Hetzner Cloud Firewall rule.
- `netbird-proxy` on `legion-node2` is public and terminates its own TLS
  (DNS-01 wildcard for `proxy.jeiang.dev`). CrowdSec IP reputation and an
  nftables bouncer protect it with decisions from the LAPI on
  `legion-node1`. The host opens TCP/UDP 40000-45000 for ad hoc services;
  each service still needs its own Hetzner Cloud Firewall rule.
- Blackbox probes target private backend addresses, never public URLs.
  Probes through the edge would get the prober banned by CrowdSec.
- Anubis gates only the static content sites. Never put it in front of a
  machine client (substituters, OIDC, NetBird gRPC, Actual sync,
  Prometheus). Its challenge store stays in memory.
- Stateless by choice: Gatus stores results in memory, and tinyauth's
  database holds only sessions.
- The H@H backup keeps the full cache: a restore costs less than earning
  back H@H trust and quota.
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

## CI

- `ci.yml` evaluates `checks.x86_64-linux`, builds each check in a matrix
  job, and pushes the results to garret on `main`. zakkart builds on a macOS
  runner. `all-checks` is the only required status.
- `dns.yml` previews DNS changes on pull requests, pushes them on merge, and
  runs a weekly drift check.
