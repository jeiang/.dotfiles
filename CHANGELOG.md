# Changelog

## Unreleased

### Fixed

- Move the host toolbox out of the wrapped Fish shell and use Cachix's pinned binary package to avoid IFD evaluation.
- Replace the pinned-store-path Cachix package (`builtins.storePath`, impure) with nixpkgs' `pkgs.cachix` — the pinned paths were old Hydra builds of the same 1.11.1 `-bin` output already cached on cache.nixos.org — and drop `--impure` from CI now that nothing violates pure evaluation.
