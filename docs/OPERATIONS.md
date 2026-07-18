# Operations

Operator setup and routine commands for this flake. Review
[`AGENTS.md`](../AGENTS.md) before changing live systems, disks, cluster
membership, or secrets.

## Development Environment

The repository expects the flake development environment from `.envrc`:

```sh
direnv allow
```

If direnv is unavailable, enter the flake shell directly:

```sh
nix develop --impure
```

Do not assume repository tools such as `just`, `statix`, `deploy`, `disko`, or
`sops` are installed globally.

## Formatting And Validation

```sh
just fmt
just check
```

`just check` may evaluate Linux-only dependencies and require a working Linux
builder when run from macOS. Prefer targeted checks over `nix flake show`, which
enumerates platform-specific outputs that are not valid on every declared
system.

## Deployment

Deploy one host explicitly:

```sh
just deploy legion-node2
```

Treat deployment, installation, disk formatting, and secret mutation as
operator actions. Review the target and generated configuration before using
`deploy`, `clean-deploy`, `install`, `disko-format`, or a `sops-*` recipe. The
fleet-wide deployment helper is not a substitute for staged node verification.

## Artemis Persistence

Artemis rolls its root btrfs subvolume back to empty on every boot. The
impermanence module does not migrate existing files into `/persist`.

After changing any Artemis `persistence.*` entry, run this on Artemis before
rebooting:

```sh
just migrate-persist
```

Re-run it after every further persistence change. A path being persistent does
not make it backed up; the off-node Backup Set is explicit and narrower than the
persistence configuration.
