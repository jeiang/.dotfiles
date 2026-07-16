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
- **README described this repo as "currently just my server."** The flake
  now also builds `artemis` (a desktop host) alongside the `legion-node*` K3s
  cluster, so the description was stale. Updated to name both.
- **MangoHud config was hjem-managed instead of wrapped.** Originally left as
  a follow-up because MangoHud's overlay can be triggered without going
  through the `mangohud` binary at all (`MANGOHUD=1` plus its Vulkan implicit
  layer, which is why nixpkgs' own package comment says it deliberately
  avoids `makeWrapper`). Confirmed the actual launch path here is always the
  `mangohud` binary, so wrapped it: `modules/packages/mangohud.nix` sets
  `MANGOHUD_CONFIGFILE` via `wrapPackage`, and `modules/nixos/gaming.nix` now
  installs the wrapped package instead of `pkgs.mangohud` plus a separate
  hjem-managed `~/.config/MangoHud/MangoHud.conf`. Verified the wrapper only
  replaces `bin/mangohud`; `lib/mangohud/libMangoHud.so`, `bin/mangoapp`,
  `bin/mangohudctl`, and the Vulkan `implicit_layer.d` JSON are symlinked
  through from the original package unchanged, so the overlay-without-the-
  binary path (if it were ever used) still works exactly as before.
- **`modules/nixos/impermanence.nix` was empty and `persistance` was a
  misspelling of "persistence".** Both follow-ups from an earlier pass are
  now resolved together: `persistance.*` was renamed to `persistence.*`
  everywhere it was declared or set (`modules/nixos/base/persistence.nix`,
  `firefox.nix`, `pipewire.nix`, `gaming.nix`), and
  `modules/nixos/impermanence.nix` now imports
  `inputs.impermanence.nixosModules.impermanence` and wires those options to
  real `environment.persistence` entries under `/persist`,
  `/persist/data/home/<user>`, and `/persist/cache/home/<user>`. Enabled on
  `artemis` only; legion hosts stay opt-in (see `persistence.enable`'s
  default and the declarative-only entries in `modules/nixos/k3s.nix`).
  `nix-community/impermanence` was chosen as the sole persistence backend —
  see the next item for why `persist-retro` was dropped instead of also
  being wired up.
- **`persist-retro` was removed as a flake input rather than adopted.** It
  was present alongside `impermanence` from the start but never wired to
  anything. `persist-retro`'s value proposition is auto-migrating
  pre-existing data into the persistent store, but that's exactly the kind
  of implicit, hard-to-audit behavior this repo wants to avoid for a
  destructive-by-construction feature — see the `persistence.*` guardrail in
  `AGENTS.md` requiring explicit, documented data copies instead.
- **Persistence options accepted invalid values until impermanence consumed
  them.** Removed the unused `persistence.volumeGroup` and
  `persistence.user` options, typed persistence entry lists as strings or
  attribute sets, and restricted `nukeRoot.maxAge` to nonnegative integers.
  Root rollback now requires persistence to be enabled and rejects empty
  device or subvolume values during NixOS evaluation. Existing Artemis
  persistence entries and rollback behavior remain unchanged.
- **Legion node details were duplicated across configuration, deployment,
  TLS, and operator helpers.** Consolidated the inventory in
  `modules/hosts/legion/default.nix`; NixOS configurations, deploy-rs nodes,
  the bootstrap server address, node TLS SANs, `just deploy-legion`, and
  `just legion-run` now derive from it. Evaluation also rejects multiple
  bootstrap nodes or duplicate node IP addresses. Node 5's existing `.6`
  private address remains unchanged pending confirmation against the live
  host.
- **Remote access and elevation policy were implicit and shared across host
  roles.** SSH now explicitly disables password and keyboard-interactive
  authentication and direct root login on every host. Artemis uses
  password-required `doas` with credential caching and a sanitized
  environment. Legion deployments connect through a dedicated, restricted-key
  `deploy` account whose passwordless sudo rule is limited to deploy-rs
  activation executables; wheel users retain password-protected sudo for
  administrative recovery. The deployment account is intentionally a Nix
  trusted user and therefore root-equivalent despite the narrower sudo rule;
  see [ADR 0001](adr/0001-treat-deployment-identity-as-privileged.md).

## Future Improvements

Listed in recommended implementation order.

1. **Harden CI cache access for pull requests.** Keep anonymous cache reads
  available so fork pull requests do not depend on GitHub OIDC permissions,
  while restricting authenticated cache writes to trusted `main` runs.
  Preserve separate checks for every `x86_64-linux` package, all NixOS
  system closures, treefmt, and statix as the workflow evolves. Keep
  unrelated lock-file and package-hash updates out of CI-only changes so
  reviews remain focused.

2. **Separate the login shell from the general-purpose toolbox.** The
  wrapped Fish login shell currently carries Cachix, devenv, and many CLI
  tools in `runtimePkgs`. Keep the shell wrapper small and move general
  tools into a system package module or the development shell. In
  particular, `cachix` pulls in a `cabal2nix`-based
  import-from-derivation step during evaluation, making evaluation from a
  non-`x86_64-linux` machine depend on a working Linux builder.

3. **Add repository-policy checks.** Once CI is in place, add inexpensive
  evaluation checks for the invariants above: every applicable NixOS system
  has a deploy target, every Legion hostname is represented in generated
  SANs, exactly one K3s node bootstraps the cluster, and root rollback cannot
  be enabled without a device. Also enable treefmt's flake check instead of
  relying only on the development-shell hook.

4. **Make the README useful for operating the flake.** Add a host and role
  matrix, development-shell instructions, formatting and validation
  commands, safe deployment examples, links to `DESIGN.md` and this file,
  and a prominent reminder that Artemis persistence changes require running
  `just migrate-persist` on Artemis before rebooting.

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
