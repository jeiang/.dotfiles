# Changelog

## Unreleased

### Added

- Zakkart: a nix-darwin host for the macOS workstation (`modules/hosts/zakkart/`, `modules/darwin/`), managed with Determinate Nix (ADR 0008) and nixpkgs-first application sourcing with Homebrew/App Store exceptions (ADR 0009). Includes a `just darwin-switch` recipe, a `checks.aarch64-darwin.zakkart-system` CI check built on a hosted macOS runner, and `docs/runbooks/zakkart-bootstrap.md`.

### Fixed

- Move the host toolbox out of the wrapped Fish shell and use Cachix's pinned binary package to avoid IFD evaluation.
- Replace the pinned-store-path Cachix package (`builtins.storePath`, impure) with nixpkgs' `pkgs.cachix` — the pinned paths were old Hydra builds of the same 1.11.1 `-bin` output already cached on cache.nixos.org — and drop `--impure` from CI now that nothing violates pure evaluation.
