# Design

Short reference for how this flake is organized and the rules to follow when
changing it. See [`docs/IMPROVEMENTS.md`](IMPROVEMENTS.md) for the audit that
motivated the current `modules/packages` / `modules/nixos` split.

## Module Boundaries

- `modules/packages/`: package definitions, overrides, and wrapped-program
  (CLI/application) configuration. A file here may define `perSystem.packages`
  outputs and, where a package needs a companion NixOS surface that is itself
  package-shaped (e.g. picking which package a service runs), may also expose
  a small `flake.nixosModules.*` output — but the bulk of system wiring
  (services, systemd units, firewall rules, filesystem layout) does not belong
  here.
- `modules/nixos/`: reusable NixOS modules — base configuration, desktop,
  K3s, sops, security, Hyprland, and related system features. These modules
  consume package outputs via `self.packages.${pkgs.stdenv.hostPlatform.system}`
  (or `self'.packages`/`selfpkgs` inside `perSystem`); they do not define
  package overrides or wrapper flags inline.
- `modules/hosts/`: host-specific NixOS, hardware, disko, and facter files.
  Host modules assemble `modules/nixos/*` and `modules/packages/*` outputs;
  they should not contain package overrides.

The rule of thumb: if a change is "which bytes make up this program," it goes
in `modules/packages`. If it's "how this system uses that program," it goes
in `modules/nixos` or `modules/hosts`.

## Package-Wrapper Policy

Several CLI tools are wrapped with `inputs.wrapper-modules.lib.wrapPackage`
(or a prebuilt wrapper from `inputs.wrapper-modules.wrappers.*`) to bake in
config files, flags, or a curated `PATH` of runtime dependencies — see
`modules/packages/{fish,git,helix,starship,hyprpaper,ghostty,dms,netbird,mangohud}.nix`.

- Prefer wrapping over separately managing a dotfile with hjem when the
  program accepts an explicit config-file flag (`--config`, `--config-file`,
  a `-C`-style startup command, or an env var like `STARSHIP_CONFIG` /
  `MANGOHUD_CONFIGFILE`). This keeps the config colocated with the package
  definition instead of split across a package output and a home-managed
  file.
- Only migrate a program to this pattern when the launch path is certain: the
  wrapped binary must be what actually gets executed everywhere the program
  is launched (system packages, desktop launchers, keybinds, systemd
  `ExecStart`, etc). Verify this here, not from general knowledge of how the
  upstream tool is normally invoked elsewhere. If a program is invoked
  through multiple launch paths and it's not certain all of them resolve to
  the wrapped package (e.g. something with a `.desktop` file from another
  package providing the binary), leave it on its current config mechanism
  and record it as a follow-up in `docs/IMPROVEMENTS.md` rather than
  guessing. `wrapPackage` only replaces the wrapped binary's own entrypoint
  and symlinks the rest of the original package's outputs through
  unchanged (via `lndir`), so wrapping a program that has *other* important
  entrypoints (other binaries, a preload library, a Vulkan/GL layer JSON,
  etc.) is safe as long as the launch path for the wrapped binary itself is
  certain — those other entrypoints keep working exactly as before, since
  they aren't touched by the wrap.
- Downstream NixOS modules should reference the wrapped package (via
  `self.packages.${system}.<name>` / `self'.packages.<name>`), never the
  underlying `pkgs.<name>` directly, once a wrapper exists for it.

## Host-Specific Change Rules

Before modifying anything under `modules/hosts/<host>/`, explicitly work
through:

1. What is the purpose of this setting?
2. Which host or workflow depends on it?
3. Should it be kept unchanged, modified, modularized, or removed?
4. If modified, what exact behavior changes as a result?

Default to preserving current behavior. If the intent isn't clear from the
code, comments, or commit history, or the change carries operational risk
(disks, networking, cluster bootstrap, secrets), stop and ask rather than
guessing. When a host-specific choice is easy to misread as a mistake
(disabled firewalls, custom kernels, raid0 with no redundancy, udev symlinks
tied to specific PCI addresses), add a short comment at the point of the
choice explaining why it's intentional, instead of moving the logic
somewhere else.

## When To Add A Custom Option

Add a typed `lib.mkOption` (with `description` and a sensible `default`) when
a setting is:

- reused across more than one module or host, or
- meant to be tuned per-host (e.g. `preferences.user.name`), or
- needed to define a clean boundary between two modules (one module declares
  the option, another consumes it, so neither needs to know the other's
  internals).

Don't add an option for a one-off constant that's only ever read in the same
module that sets it — inline it. An option with a single call site and no
plausible second caller is indirection without payoff.
