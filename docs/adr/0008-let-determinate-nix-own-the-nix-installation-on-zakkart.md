# Let Determinate Nix own the Nix installation on Zakkart

Zakkart (the macOS workstation) is managed by nix-darwin from this flake, but
the Nix installation itself is not: Determinate Nix is installed with its own
installer and manages the daemon, upgrades, and `/etc/nix/nix.conf`, with
nix-darwin setting `nix.enable = false`. Flake-side Nix customization
(substituters, trusted keys, registry pinning) flows through Determinate's
custom-configuration mechanism instead of nix-darwin's `nix.*` module. The
alternative — letting nix-darwin manage a nixpkgs Nix, matching the NixOS
hosts — was rejected because the operator intends to move the NixOS fleet to
Determinate Nix as well; Zakkart is the first host on that path, and macOS is
where an installer-managed Nix (survives OS updates, clean uninstall) pays
off most.

## Consequences

- The darwin config cannot use nix-darwin `nix.*` options; settings that
  `modules/nixos/nix.nix` expresses for NixOS hosts need a parallel
  Determinate-compatible expression, and the two can drift until the NixOS
  fleet also moves to Determinate.
- Bootstrapping a reset machine starts with the Determinate installer, not
  with any output of this flake.
- Nix version upgrades on Zakkart arrive on Determinate's schedule, not on
  flake.lock bumps.
