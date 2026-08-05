# Adopt Determinate Nix on the NixOS fleet

Zakkart (the macOS workstation) moved to Determinate Nix in docs/adr/0008,
which called out the config drift between its Determinate-specific
expression and the NixOS hosts' `nix.*` settings, and named finishing the
move onto the NixOS fleet as the closing move. This ADR closes that gap: all
NixOS hosts (legion-node1..4, artemis) now import Determinate's NixOS
module.

Unlike the darwin module, the Determinate NixOS module keeps the stock
NixOS `nix.*` options fully active — it retargets the generated nix.conf to
`/etc/nix/nix.custom.conf`, sets `nix.package` to Determinate Nix, and
rewires `nix-daemon.service`'s `ExecStart` to `determinate-nixd`. It does
not rewrite settings into a separate Determinate-only mechanism the way the
darwin module does. So `modules/nixos/nix.nix`'s existing `nix.settings`
(substituters, trusted keys, registry pinning, etc.) carries over unchanged;
no parallel Determinate-compatible expression is needed on NixOS.

## Consequences

- Nix's version on the fleet now comes from the `determinate` flake input
  rather than nixpkgs, so `flake.lock` bumps to that input are how Nix
  itself is upgraded going forward.
- `determinate-nixd` owns `/etc/nix/nix.conf` and the `nix-daemon.service`
  `ExecStart`, in place of stock nixpkgs Nix.
- The bare `substituters` list in `modules/nixos/nix.nix` still overrides
  Determinate's default substituters, same as before this change (attic,
  helix, hyprland caches only) — behavior is unchanged.
