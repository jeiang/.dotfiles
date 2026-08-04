# Changelog

## Unreleased

### Added

- Zakkart: a nix-darwin host for the macOS workstation (`modules/hosts/zakkart/`, `modules/darwin/`), managed with Determinate Nix (ADR 0008) and nixpkgs-first application sourcing with Homebrew/App Store exceptions (ADR 0009). Includes a `just darwin-switch` recipe, a `checks.aarch64-darwin.zakkart-system` CI check built on a hosted macOS runner, and `docs/runbooks/zakkart-bootstrap.md`.

### Fixed

- Add the operator account to `users.knownUsers` (uid 501) on zakkart so the wrapped-fish login shell actually applies -- nix-darwin only writes `UserShell` for known users, so the previous bare `users.users.<name>.shell` was silently ignored and the account stayed on `/bin/zsh`.
- Declare `trusted: true` on every Brewfile tap entry so Homebrew >= 6.0's tap-trust enforcement doesn't refuse to load formulae/casks from the pinned third-party taps (`netbirdio/tap`, `can1357/tap`, `k06a/tap`) during activation.
- Move the host toolbox out of the wrapped Fish shell and use Cachix's pinned binary package to avoid IFD evaluation.
- Replace the pinned-store-path Cachix package (`builtins.storePath`, impure) with nixpkgs' `pkgs.cachix` — the pinned paths were old Hydra builds of the same 1.11.1 `-bin` output already cached on cache.nixos.org — and drop `--impure` from CI now that nothing violates pure evaluation.
