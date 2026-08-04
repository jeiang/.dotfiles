# Changelog

## Unreleased

### Added

- Zakkart: a nix-darwin host for the macOS workstation (`modules/hosts/zakkart/`, `modules/darwin/`), managed with Determinate Nix (ADR 0008) and nixpkgs-first application sourcing with Homebrew/App Store exceptions (ADR 0009). Includes a `just darwin-switch` recipe, a `checks.aarch64-darwin.zakkart-system` CI check built on a hosted macOS runner, and `docs/runbooks/zakkart-bootstrap.md`.
- Zakkart macOS preferences (`modules/darwin/preferences.nix`): dock moved right with autohide and hot corners, menu bar mirroring the observed macOS 26 values, pink accent/highlight colors, the application firewall, the repo's `assets/wallpaper.jpg`, Helium as the default browser via `defaultbrowser`, the built-in display scaled to "More Space" via `displayplacer`, and the Spotlight (Cmd+Space) hotkey disabled — per `docs/adr/0010-script-user-scoped-macos-preferences-nix-darwin-cannot-express.md`.

### Fixed

- Prepend the nix-darwin profile paths (`~/.nix-profile/bin`, `/etc/profiles/per-user/$USER/bin`, `/run/current-system/sw/bin`, `/nix/var/nix/profiles/default/bin`) in the wrapped fish's darwin config -- macOS login shells start from `path_helper`'s PATH, so `environment.systemPackages` tools (first symptom: `direnv hook fish` at startup) were unreachable. Linux config text is unchanged.
- Add the operator account to `users.knownUsers` (uid 501) on zakkart so the wrapped-fish login shell actually applies -- nix-darwin only writes `UserShell` for known users, so the previous bare `users.users.<name>.shell` was silently ignored and the account stayed on `/bin/zsh`.
- Declare `trusted: true` on every Brewfile tap entry so Homebrew >= 6.0's tap-trust enforcement doesn't refuse to load formulae/casks from the pinned third-party taps (`netbirdio/tap`, `can1357/tap`, `k06a/tap`) during activation.
- Move the host toolbox out of the wrapped Fish shell and use Cachix's pinned binary package to avoid IFD evaluation.
- Replace the pinned-store-path Cachix package (`builtins.storePath`, impure) with nixpkgs' `pkgs.cachix` — the pinned paths were old Hydra builds of the same 1.11.1 `-bin` output already cached on cache.nixos.org — and drop `--impure` from CI now that nothing violates pure evaluation.
- Export `DIRENV_CONFIG` in the wrapped fish's darwin login shells -- the wrapped fish never sourced nix-darwin's `set-environment`, so nix-direnv's loader (`/etc/direnv/direnvrc`) never loaded and `use flake` silently fell back to direnv's builtin, uncached implementation, re-evaluating dev shells on every prompt.
