# Design

This flake is the single-operator source of truth for the Artemis workstation
and Legion service hosts, not a reusable NixOS framework. This document records
its architecture and design rules. See [`CONTEXT.md`](../CONTEXT.md) for
canonical terms and [`docs/IMPROVEMENTS.md`](IMPROVEMENTS.md) for open work.

## System Roles

| System | Current role | Accepted direction |
| --- | --- | --- |
| `artemis` | Performance-oriented workstation with an impermanent root | Remain a recoverable workstation with explicit off-node backups |
| `legion-node1` | K3s server and bootstrap node | Become the single Caddy Edge Node |
| `legion-node2` through `legion-node4` | K3s agents | Host explicitly assigned NixOS services |
| `legion-node5` | K3s agent | Decommission after service migration |

Artemis's custom kernel, desktop stack, gaming and VR configuration,
impermanent root, and hardware-specific rules are intentionally host-specific.

The single K3s server is intentional because each Legion node has roughly 2 GB
of RAM and the other four nodes need that memory for workloads. The personal
services in K3s are transitional rather than a commitment to Kubernetes as
their final runtime. The accepted target is a four-node Legion Fleet of
Host-Native Services. See
[ADR 0002](adr/0002-migrate-legion-to-host-native-services.md).

Current configuration must continue to describe the Experimental Cluster until
each migration step lands. Do not write target-state documentation as though it
were already deployed.

## Module Boundaries

- `modules/packages/`: package definitions, overrides, and wrapped-program
  configuration. A file here may define `perSystem.packages` outputs and, where
  a package needs a small package-shaped NixOS surface, may also expose a
  `flake.nixosModules.*` output. System wiring such as services, systemd units,
  firewall rules, and filesystem layout does not belong here.
- `modules/nixos/`: reusable NixOS modules for base configuration, desktop,
  K3s, sops, security, Hyprland, and related system features. These modules
  consume package outputs through
  `self.packages.${pkgs.stdenv.hostPlatform.system}` or the corresponding
  `self'.packages`/`selfpkgs` surface. They do not define package overrides or
  wrapper flags inline.
- `modules/hosts/`: host-specific NixOS, hardware, disko, and facter files. Host
  modules assemble the reusable modules and package outputs; they should not
  contain package overrides.

The rule of thumb: if a change is "which bytes make up this program," it goes in
`modules/packages`. If it is "how this system uses that program," it goes in
`modules/nixos` or `modules/hosts`.

## Service Ownership

For Host-Native Services, this repository owns the NixOS module, node
assignment, runtime configuration, state mounts, secret delivery, firewall
rules, backup declaration, and service lifecycle. Application source remains in
the application repository.

Prefer a first-party NixOS module when it fits the deployed architecture. Use a
local composition module when several first-party modules must be configured as
one service boundary. Write a custom service module when no suitable module
exists or the first-party abstraction models a materially different topology.
Do not retain an OCI container merely to avoid a small systemd service module.

Service placement belongs in the central Legion inventory. Exactly one node
owns each stateful service, and moving it is an explicit state migration rather
than scheduler-driven failover.

## State And Backup Boundaries

Persistence and backup solve different problems. Persistent State survives a
reboot or rebuild; a Backup Set permits recovery after the persistent storage is
lost.

- Host-Native Service state belongs on directly mounted Hetzner Volumes. Local
  node storage is for Disposable State.
- Backup Sets are explicit allowlists. Do not infer that every persistent path
  should be backed up.
- When repository-managed persistence is enabled for a host, its Backup Set
  must be a subset of that persistence configuration.
- Runtime service secrets use sops-nix files encrypted only to the Human
  Administrator and assigned host. Do not give every host access to every
  application secret.

DNS, Hetzner Cloud Firewalls, servers, and Volumes are provisioned outside this
flake. Configuration here may depend on their stable names and identifiers, but
must document those external prerequisites.

## Package-Wrapper Policy

Several CLI tools are wrapped with `inputs.wrapper-modules.lib.wrapPackage` or a
prebuilt wrapper from `inputs.wrapper-modules.wrappers.*` to bake in config
files, flags, or a curated `PATH` of runtime dependencies.

- Prefer wrapping over separately managing a dotfile with hjem when the program
  accepts an explicit config-file flag, startup command, or environment variable.
  This keeps configuration beside the package definition.
- Only migrate a program to this pattern when the launch path is certain. The
  wrapped binary must be what executes from system packages, desktop launchers,
  keybinds, and systemd units. If multiple launch paths exist and the repo does
  not prove that they use the wrapper, keep the current mechanism and record the
  uncertainty in `docs/IMPROVEMENTS.md`.
- `wrapPackage` replaces the selected binary entry point and symlinks the other
  package outputs through unchanged. Other binaries, libraries, and metadata
  remain available from the original package.
- Once a wrapper exists, downstream NixOS modules reference the wrapped package
  through this flake rather than the underlying `pkgs.<name>`.

## Host-Specific Change Rules

Before modifying anything under `modules/hosts/<host>/`, answer:

1. What is the purpose of this setting?
2. Which host or workflow depends on it?
3. Should it remain, change, move, or be removed?
4. What exact behavior changes as a result?

Default to preserving current behavior. If intent is not clear from code,
comments, or history, or if the change affects disks, networking, cluster
bootstrap, or secrets, stop and ask. When a host-specific choice is easy to
misread as a mistake, add a short source comment explaining why it is
intentional instead of moving it into a generalized abstraction.

## Intentional Host Decisions

- Legion enables the NixOS firewall (`modules/hosts/legion/hardware.nix`,
  ADR 0002 / `docs/MIGRATION.md` piece 0.2), rather than relying solely on
  the Hetzner Cloud Firewall. Openings are derived in
  `modules/hosts/legion/default.nix` from the Legion service inventory
  (`service-inventory.nix`) plus the live K3s-era data path documented
  there.
- Legion intentionally has one K3s server. Control-plane high availability
  would consume RAM needed for experimentation and transitional workloads.
- `legion-node5` intentionally uses private address `172.17.0.6`; do not close
  the gap at `.5` while the node remains live.
- Artemis uses a host-specific CachyOS kernel built for its Zen 4 CPU with the
  BORE scheduler, full LTO, and an AutoFDO profile.
- Artemis stripes root across three NVMe drives with btrfs RAID0. Local
  redundancy is deliberately traded for throughput; irreplaceable data must be
  protected by the explicit off-node Backup Set.
- Artemis GPU symlinks depend on its PCI addresses so display configuration can
  use stable integrated and discrete GPU paths.
- Artemis gaming and VR modules encode its Moza wheel, GPU, and headset setup;
  they are not general-purpose modules despite their location under
  `modules/nixos`.

## When To Add A Custom Option

Add a typed `lib.mkOption` with a description and sensible default when a
setting is:

- reused across more than one module or host;
- meant to be tuned per host; or
- needed to define a clean boundary between modules.

Do not add an option for a one-off constant that is only read in the module that
sets it. A single-call-site option with no plausible second caller is
indirection without payoff.
