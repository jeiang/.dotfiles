# Source macOS applications nixpkgs-first with declared exceptions

Applications on Zakkart come from nixpkgs whenever the package works on
`aarch64-darwin`; everything else comes from one of two declared exception
channels, both driven from the darwin config. Homebrew casks (Homebrew itself
installed by nix-homebrew, with `homebrew-core`/`homebrew-cask` pinned as
flake inputs, `mutableTaps = false`, and `onActivation.cleanup = "zap"`)
cover apps with no working nixpkgs darwin package (Helium, ChatGPT, Claude,
CrossOver, Actual, GIMP, balenaEtcher, Microsoft Word/Excel, Roblox) and apps
where self-updating matters more than pinning (WhatsApp — Meta locks out
stale builds). Mac App Store apps via `homebrew.masApps` cover store-only or
deliberately sandboxed apps: Yubico Authenticator, Wipr, and Bitwarden.
Bitwarden is deliberately the App Store build, not the cask or the nixpkgs
package: the sandboxed build is the proven working setup, ships the Safari
extension, and auto-updates — accepting that its SSH-agent socket lives at
the container path (`~/Library/Containers/com.bitwarden.desktop/Data/`)
rather than `~/.bitwarden-ssh-agent.sock`, a per-platform difference the
wrapped fish environment resolves at eval time.

## Consequences

- `brew tap` and ad-hoc `brew install` are impossible or reverted: tap
  updates arrive only via flake.lock bumps, and undeclared packages are
  zapped (removed with their data) on activation.
- Cask-installed apps still self-update their binaries (`auto_updates`);
  only the cask definitions are pinned, so the installed app version is not
  fully determined by the flake.
- nixpkgs-sourced GUI apps are version-pinned to flake.lock and update only
  on input bumps.
- Anything outside all three channels (e.g. Jackbox titles) is an
  unmanaged manual install by definition.
