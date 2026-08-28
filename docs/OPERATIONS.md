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

## Remote Access

- Legion nodes: `node1.jeiang.dev` through `node4.jeiang.dev`. The nodes are
  ephemeral, so NetBird assigns them semi-random mesh names (this allows
  re-provisioning without conflicts); the public DNS names are the stable
  handles.
- Artemis: `artemis.jeiang.vpn`. Bare `artemis` resolves through the wildcard
  DNS record and does not reach the host.
- The default shell on every machine is fish. Wrap POSIX one-liners run over
  SSH in `bash -c '...'`; commands written for the operator use fish syntax.
- Legion nodes use `sudo` (password required); artemis uses `doas`. Neither is
  scriptable non-interactively; privileged commands are run by the operator.

## Deployment

Deploy one host explicitly:

```sh
just deploy legion-node2
```

When the deploying machine and the target differ in system type (deploying
x86_64-linux hosts from macOS, or vice versa), add `--skip-checks
--remote-build`; `--skip-checks` avoids building and running checks that are
incompatible with the local machine. Deploy
only after the change is merged and CI has pushed closures to garret, so the
target substitutes instead of building.

Treat deployment, installation, disk formatting, and secret mutation as
operator actions. Review the target and generated configuration before using
`deploy`, `clean-deploy`, `install`, `disko-format`, or a `sops-*` recipe. The
fleet-wide deployment helper is not a substitute for staged node verification.

Legion runs Host-Native Services placed per the Legion inventory
(`modules/hosts/legion/_service-inventory.nix`). See
[`docs/runbooks/`](runbooks/) for operator runbooks, including backup
restore.

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

`just migrate-persist` (`modules/hosts/artemis/migrate-persist.sh`) copies
existing state into `/persist` from the live `persistence.*` configuration. It
must run on Artemis itself, not from a dev checkout. The module never migrates
state on its own.

## Secrets

- `just sops-edit` opens a secrets file and keys new entries automatically.
- `just sops-updatekeys` is only needed after changing recipients in
  `.sops.yaml`.

## CI Secrets

- `FLAKE_LOCK_PAT`: fine-grained PAT used by
  `.github/workflows/update-flake-inputs.yml` so its flake-lock update PRs
  trigger CI (the default `GITHUB_TOKEN` cannot trigger further workflow runs).
  **Expires 2027-07-22** — rotate it before then, or the workflow's PRs will
  stop getting CI runs with no obvious error.
- `FLAKE_LOCK_GPG_PRIVATE_KEY`: ASCII-armored private key for a dedicated
  `flake-lock-bot` GPG key, used by the same workflow to sign its commits
  (`main` requires signed commits, so unsigned bot commits can't be merged).
  The key's UID email must be a verified email on the account holding
  `FLAKE_LOCK_PAT` (this repo uses that account's GitHub-provided
  `<id>+<login>@users.noreply.github.com` address, which is verified
  automatically with no separate confirmation step), and its public half must
  be added as a GPG key on that same account.
