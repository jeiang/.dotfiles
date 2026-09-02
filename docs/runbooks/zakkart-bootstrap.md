# Runbook: Zakkart Bootstrap

Rebuild Zakkart (the macOS workstation, `modules/hosts/zakkart/default.nix`)
from a reset Mac. Review [`AGENTS.md`](../../AGENTS.md) before running any
command here.

Nix itself comes from the Determinate installer rather than from this flake
([ADR 0008](../adr/0008-let-determinate-nix-own-the-nix-installation-on-zakkart.md));
some apps come from Homebrew or the Mac App Store rather than nixpkgs
([ADR 0009](../adr/0009-source-macos-applications-nixpkgs-first-with-declared-exceptions.md)).

The steps are ordered: 3 before 5, or the App Store installs silently skip.

## 1. Reset macOS

Erase and reinstall through the normal recovery/Migration Assistant flow. Do
not restore an Application/App Data backup for anything this flake manages —
a restored copy fights `homebrew.onActivation.cleanup = "zap"`.

## 2. Install Determinate Nix

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

It owns the daemon and `/etc/nix/nix.conf` from here on; nix-darwin's own
`nix.*` options never apply on this host (ADR 0008).

## 3. Sign into the App Store

Sign in with the Apple ID that owns the `homebrew.masApps` entries
(Bitwarden, Yubico Authenticator, Wipr 2) **before** the first activation.
`mas` only installs for a signed-in account, and `programs.mas` swallows the
"not signed in" failure — activation would skip the App Store apps with no
error and need a second `darwin-switch` afterward.

## 4. Clone the repo

```sh
git clone <this repo> ~/Projects/cornn-flaek
cd ~/Projects/cornn-flaek
```

## 5. First activation

`darwin-rebuild` isn't installed yet, so the first switch runs it out of the
upstream nix-darwin flake; the system config still comes from `--flake
.#zakkart`, i.e. this repo.

The substituters in `modules/darwin/nix.nix` only take effect once
activation has written `/etc/nix/nix.custom.conf`, so pass them explicitly
or this first build compiles everything from source:

```sh
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#zakkart \
  --option extra-substituters "https://cache.jeiang.dev https://helix.cachix.org" \
  --option extra-trusted-public-keys "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA= helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
```

This installs Homebrew (via nix-homebrew) and its taps/casks/brews/App Store
apps — including the NetBird desktop client cask, which installs its own
system daemon on first run (ADR 0009) — sets the login shell, and every
other piece in `modules/darwin/`.

Subsequent switches need no flags; the previous activation's config is
already in `/etc/nix/nix.custom.conf`:

```sh
just darwin-switch
```

Don't reach for `brew trust` by hand. Homebrew >= 6.0 requires unofficial
taps to be trusted before their formulae/casks load, and the generated
Brewfile already declares `trusted: true` for every tap
(`modules/darwin/homebrew.nix`) — all pinned flake inputs, so it trusts
exactly the revisions in `flake.lock`. The `cleanup = "zap"` pass resets
Homebrew's trust file to the Brewfile on every activation anyway.

## 6. Bitwarden SSH agent

Sign into the Bitwarden app (the Mac App Store build, ADR 0009) and enable
its SSH agent in Settings. The socket appears at:

```
~/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock
```

`SSH_AUTH_SOCK` points there unconditionally on darwin
(`modules/packages/fish.nix`), so a fresh shell picks it up as soon as the
socket exists.

## 7. sops age key

Place the operator's age private key at the path `modules/darwin/sops.nix`
configures as `sops.age.keyFile`:

```
/var/lib/sops-nix/key.txt
```

## 8. Wallpaper rotation

Activation symlinks `~/Pictures/Wallpapers` to the recolored wallpaper set
(`modules/darwin/preferences.nix`). The rotation itself is a macOS setting
nothing scriptable reaches, so set it once by hand:

System Settings > Wallpaper > Add Photo (the "+" under the wallpaper
picker) > Add Folder or Album > Add Folder > pick `~/Pictures/Wallpapers`.
Then, on that folder entry: rotation "Every 30 Minutes", Shuffle on, and
"Show on all Spaces" on.

If a later palette change swaps the store path behind the symlink and macOS
stops rotating, redo this step.

## 9. Verify

```sh
dscl . -read /Users/aidanp UserShell   # should end in .../bin/fish (the wrapped environment package)
echo $SSH_AUTH_SOCK                     # .../Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock
brew list --cask                        # matches modules/darwin/homebrew.nix's `casks`
brew list --formula                     # matches `brews`
mas list                                # matches `masApps`
```

NetBird is the cask (`netbirdio/tap/netbird-ui`), not a nix-managed daemon —
it installs and manages its own system service on first launch. Open the
app, sign in, and check the menu bar shows "Connected"; there's no
`launchctl`/`netbird status` check unless you separately install the CLI.
