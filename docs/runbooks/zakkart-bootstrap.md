# Runbook: Zakkart Bootstrap

Operator runbook for bringing up Zakkart (the macOS workstation,
`modules/hosts/zakkart/default.nix`) from a reset Mac. Review
[`AGENTS.md`](../../AGENTS.md) before running any command here. This is a
recurring runbook -- the machine can be re-bootstrapped from scratch any
time, there's no one-shot state to lose track of.

See [`docs/adr/0008-let-determinate-nix-own-the-nix-installation-on-zakkart.md`](../adr/0008-let-determinate-nix-own-the-nix-installation-on-zakkart.md)
for why Nix itself comes from the Determinate installer rather than from
this flake, and
[`docs/adr/0009-source-macos-applications-nixpkgs-first-with-declared-exceptions.md`](../adr/0009-source-macos-applications-nixpkgs-first-with-declared-exceptions.md)
for why some apps come from Homebrew or the Mac App Store instead of
nixpkgs.

## 1. Reset macOS

Erase and reinstall macOS through the normal recovery/Migration Assistant
flow. Do not restore an Application/App Data backup for anything this flake
manages -- Homebrew casks and the App Store apps below get reinstalled
declaratively; a restored copy would fight `homebrew.onActivation.cleanup =
"zap"`.

## 2. Install Determinate Nix

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Determinate Nix owns the daemon and `/etc/nix/nix.conf` from here on;
nix-darwin's own `nix.*` options never apply on this host (ADR 0008).

## 3. Sign into the App Store

Open the App Store app and sign in with the Apple ID that owns the
`homebrew.masApps` entries (Bitwarden, Yubico Authenticator, Wipr 2) before
the first activation. `mas` can only install/update apps for a signed-in
account; if activation runs before this step, the App Store installs are
silently skipped (see `programs.mas`'s own handling of a `mas list`
"not signed in" failure) and need a second `darwin-switch` afterward.

## 4. Clone the repo

```sh
git clone <this repo> ~/Projects/cornn-flaek
cd ~/Projects/cornn-flaek
```

## 5. First activation

`darwin-rebuild` isn't installed yet, so the first switch runs it straight
out of the upstream nix-darwin flake (this only bootstraps the binary; the
actual system config still comes from `--flake .#zakkart`, i.e. this repo).

The cache/attic/helix substituters (`modules/darwin/nix.nix`) only take
effect *after* activation writes `/etc/nix/nix.custom.conf` -- they aren't
active yet for this first run. Pass them explicitly with `--option` so the
very first build substitutes instead of compiling everything from source:

```sh
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#zakkart \
  --option extra-substituters "https://cache.jeiang.dev https://attic.jeiang.dev/default https://helix.cachix.org" \
  --option extra-trusted-public-keys "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA= default:Xaqeg5b1ctNwH4sEWG+nt1kSpGPpFG0zivJUbZyCfdM= helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
```

Every subsequent `just darwin-switch` no longer needs these flags -- the
config from the previous activation is already in `/etc/nix/nix.custom.conf`.

This installs Homebrew (via nix-homebrew) and Nix-homebrew's taps/casks/
brews/App Store apps -- including the NetBird desktop client cask, which
installs its own system daemon on first run (ADR 0009) -- sets the login
shell, and every other piece in `modules/darwin/`. Subsequent switches use:

```sh
just darwin-switch
```

Homebrew >= 6.0 requires unofficial taps to be trusted before their
formulae/casks load. The generated Brewfile declares `trusted: true` for
every tap (`modules/darwin/homebrew.nix`) -- they're all pinned flake
inputs, so this trusts exactly the revisions in `flake.lock`. Don't reach
for `brew trust` by hand: the `cleanup = "zap"` pass resets Homebrew's
trust file to what the Brewfile declares on every activation.

## 6. Bitwarden SSH agent

Sign into the Bitwarden app (installed via `homebrew.masApps`, the Mac App
Store build -- ADR 0009) and enable its SSH agent in Settings. The agent's
socket appears at:

```
~/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock
```

`SSH_AUTH_SOCK` is pointed at this path unconditionally on darwin by the
wrapped fish config (`modules/packages/fish.nix`), so a fresh shell picks it
up as soon as the socket exists -- no further configuration needed.

## 7. sops age key

Place the operator's age private key at the path `modules/darwin/sops.nix`
configures (`sops.age.keyFile`):

```
/var/lib/sops-nix/key.txt
```

No secrets are declared on zakkart yet; this just gets the key in place
ahead of the first one.

## 8. Verify

```sh
dscl . -read /Users/aidanp UserShell   # should end in .../bin/fish (the wrapped environment package)
echo $SSH_AUTH_SOCK                     # .../Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock
brew list --cask                        # matches modules/darwin/homebrew.nix's `casks`
brew list --formula                     # matches `brews`
mas list                                # matches `masApps`
```

NetBird is the cask (`netbirdio/tap/netbird-ui`), not a nix-managed
daemon -- it installs and manages its own system service on first launch.
Open the NetBird app, sign in, and check the menu bar icon shows
"Connected"; there's no `launchctl`/`netbird status` check to run from the
shell unless you separately install the CLI.
