# Improvements

Findings from a pass over module organization, grouped by what was fixed in
this refactor, what's left as a follow-up, and host-specific choices that are
intentional and should not be "fixed" without explicit sign-off. See
[`docs/DESIGN.md`](DESIGN.md) for the resulting module boundaries and rules.

## Fixed Now

- **Netbird override lived in a system module.** `modules/nixos/netbird.nix`
  built its own `pkgs.netbird.overrideAttrs` inline. Moved the override to
  `modules/packages/netbird.nix` as `packages.<system>.netbird`; the NixOS
  module now consumes `self.packages.${system}.netbird`.
- **DMS mixed package and NixOS module concerns.** `dms.nix` used to define
  both `packages.dms`/`packages.dsearch` and `flake.nixosModules.dankmaterialshell`
  in one file under the wrapped-programs directory. Split them:
  `modules/packages/dms.nix` keeps the package outputs, and
  `modules/nixos/dankmaterialshell.nix` has the NixOS module (same output
  name, `nixosModules.dankmaterialshell`, so no downstream references
  changed).
- **Ghostty had a wrapper, but desktop code used plain `pkgs.ghostty`.**
  `modules/nixos/desktop.nix` installed `pkgs.ghostty` directly and separately
  hjem-managed `~/.config/ghostty/config.ghostty`, while a mostly-empty
  `flake.wrapperModules.ghostty` wrapper sat unused. Consolidated: the Ghostty
  config now lives in the wrapper (`modules/packages/ghostty.nix`, via
  `--config-file`), the home-managed config file was removed, and both
  `desktop.nix`'s `systemPackages` entry and the Hyprland terminal launch
  path (`modules/nixos/hyprland/default.nix`) now reference the wrapped
  `self.packages.${system}.ghostty` package. Also removed a stray
  `packages.terminal = pkgs.ghostty` (unwrapped) that `hyprland/default.nix`
  had been reading the terminal binary from instead of the wrapper.
- **`modules/wrappedPrograms/` renamed to `modules/packages/`.** The old name
  undersold what lived there (package overrides, not just wrappers) and read
  as parallel to, rather than complementary to, `modules/nixos/`.
  `AGENTS.md` updated to match.
- **Unused `flake.wrapperModules` option removed.** It existed only to
  support the old Ghostty `evalModule`-based wrapper; once that wrapper was
  simplified to `wrapPackage` (matching every other wrapper in the repo), the
  option in `modules/parts.nix` had no remaining callers.

## Follow-Up Candidates

- **MangoHud config is still hjem-managed, not wrapped.** `modules/nixos/gaming.nix`
  writes `~/.config/MangoHud/MangoHud.conf` via hjem rather than baking the
  config into a wrapped `mangohud` package. MangoHud is typically invoked via
  `mangohud <game-command>` or `LD_PRELOAD` from many different launch paths
  (Steam launch options, Heroic, Prism Launcher, gamescope), so it isn't
  certain that a single wrapped binary would be picked up everywhere it's
  used. Left as-is; revisit if/when all launch paths are confirmed to go
  through one wrapped binary.
- **`modules/nixos/impermanence.nix` is empty.** It declares
  `flake.nixosModules` for nothing — no `impermanence` module is defined
  there, and the `persistance.*` options declared in
  `modules/nixos/base/persistence.nix` (see next item) are never consumed by
  anything that actually wires up `nix-community/impermanence` or
  `persist-retro` (both present as flake inputs). Several modules
  (`firefox.nix`, `pipewire.nix`, `gaming.nix`) set `persistance.data.*` /
  `persistance.cache.*` values that currently have no effect. This needs a
  real design decision (which persistence backend, how directories map to
  bind mounts) before it's touched, so it's left for a follow-up rather than
  guessed at here.
- **`persistance` option name is a likely misspelling of "persistence".**
  Declared in `modules/nixos/base/persistence.nix` and used in three other
  modules. Renaming is a mechanical but repo-wide change with no behavioral
  effect while the options remain unwired (see above) — bundling the rename
  with actually wiring up impermanence avoids a second churn pass.
- **README still describes this repo as "currently just my server."** The
  flake now also builds `artemis` (a desktop host) alongside the `legion-node*`
  K3s cluster, so the description is stale. Left unchanged here since it's
  user-facing prose rather than module organization, and out of scope for
  this refactor's Key Changes.

## Intentional Host Context

These are host-specific choices that look surprising out of context but are
deliberate. Comments were added at the point of each choice in this pass
where none previously existed; do not "fix" these without discussing the
underlying tradeoff first, per the host-specific change rules in
[`docs/DESIGN.md`](DESIGN.md).

- **Legion nodes disable the NixOS firewall.**
  (`modules/hosts/legion/hardware.nix`) Hetzner's Cloud Firewall manages
  traffic to these nodes at the infrastructure level, so an in-VM firewall
  would be redundant. Already commented in the source.
- **Artemis runs a custom CachyOS kernel build.**
  (`modules/hosts/artemis/default.nix`) Built specifically for this host's
  zen4 CPU with the BORE scheduler, full LTO, and an AutoFDO profile
  (`kernel.afdo`) — desktop-only performance tuning, not portable to other
  hosts as-is. Comment added in this pass.
- **Artemis stripes root across 3 NVMe drives with btrfs raid0, no
  redundancy.** (`modules/hosts/artemis/disko.nix`) Deliberate throughput
  choice for a desktop workstation; a single drive failure loses data by
  design. Comment added in this pass.
- **Artemis creates udev symlinks for `/dev/dri/egpu` and `/dev/dri/igpu`
  keyed to specific PCI addresses.** (`modules/hosts/artemis/hardware.nix`)
  Lets Hyprland/niri pick a specific GPU by a stable path instead of the
  `cardN` enumeration order, which can change across boots. Already commented
  in the source.
- **Artemis's VR and gaming setup (`modules/nixos/gaming.nix`'s `vr`/`gaming`
  NixOS modules) are host-specific by design,** not general-purpose modules —
  they encode this host's specific hardware (Moza wheel udev rules, GPU
  device index for gamemode) and are only imported by
  `artemisConfiguration`.
