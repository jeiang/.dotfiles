# Script user-scoped macOS preferences nix-darwin cannot express

Zakkart's desktop preferences (`modules/darwin/preferences.nix`) use
`system.defaults` wherever the pinned nix-darwin rev has an option that
writes the same value macOS itself reads: dock placement/autohide/hot
corners, the menu bar clock, `controlcenter.BatteryShowPercentage`, and the
pink accent/highlight colors via `CustomUserPreferences.NSGlobalDomain`.
Everything else is scripted in `system.activationScripts.postActivation.text`
using nix-darwin's own user-context pattern (`launchctl asuser "$(id -u --
<user>)" sudo --user=<user> -- <cmd>`, since all activation otherwise runs as
root and `postUserActivation` was removed from this rev): the three menu bar
`controlcenter` items nix-darwin can't express faithfully, the Spotlight
(Cmd+Space) symbolic hotkey, the wallpaper, the default browser, and the
built-in display's scaled resolution. `controlcenter.Bluetooth` is the
clearest case for scripting over the option: the pinned nix-darwin writes the
pre-macOS-26 constant (18) for that option, not the value macOS 26 actually
reads at `-currentHost` (2) — using the option would silently converge to
the wrong menu bar state on every activation. Steps that touch TCC consent,
LaunchServices, or WindowServer (wallpaper via System Events automation,
default browser, display scaling) warn and continue on failure rather than
aborting activation, since a denied or not-yet-granted consent dialog isn't
a configuration error; the deterministic `defaults` writes still fail loudly
under activation's `set -e`. One-time TCC and default-browser confirmation
dialogs on first activation (or after a TCC reset) are accepted as an
expected side effect. Night Shift is deliberately left unmanaged: its
schedule lives in a private CoreBrightness plist format with no documented
`defaults` keys, so scripting it would mean reverse-engineering an
undocumented binary format for a single toggle.

## Consequences

- A TCC reset (or a fresh machine) re-prompts for System Events automation
  and default-browser consent on the next activation; that's expected, not a
  bug.
- The observed constants this ADR hardcodes (`Bluetooth = 2`, `Spotlight =
  8`, `Weather = 2`, hotkey `64`) are macOS 26 values verified live on this
  machine; a future macOS major can change them, and the fix is to
  re-observe and update the activation script, not to expect nix-darwin's
  options to catch up.
- These steps converge state on every activation rather than enforcing it
  continuously — a user can change any of them by hand between activations,
  and the next `darwin-switch` will silently reassert the declared value.
- Activation stays non-interactive-safe: no step blocks on a dialog, and a
  denied consent degrades to a warning instead of failing the whole switch.
- Night Shift stays a manual, undeclared setting; it won't survive a fresh
  machine bootstrap.

## References

- Homebrew fallback policy for `displayplacer`: `docs/adr/0009-source-macos-applications-nixpkgs-first-with-declared-exceptions.md`.
