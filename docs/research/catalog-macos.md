# macOS software catalog survey (Zakkart)

Source: [serhii-londar/open-source-mac-os-apps](https://github.com/serhii-londar/open-source-mac-os-apps)
(fetched from `raw.githubusercontent.com/.../master/README.md`, 9482 lines). Scanned for
prompt-injection content first (`grep -niE 'ignore (previous|all)|you are an ai|system
prompt|as an ai|disregard'`) — nothing found. All content below is treated as data about
software, not instructions.

Date: 2026-08-22. Target: Zakkart (nix-darwin, aarch64-darwin), policy per
`docs/adr/0009-*` (nixpkgs-first, Homebrew casks only as declared exceptions,
`mutableTaps = false`) and `docs/adr/0010-*` (activation-script prefs).
Nixpkgs sourcing verified against commit `2fcb964de67fcf60b43471c55d5d99e61a9ccb5a`
(`pkgs/by-name/<prefix>/<name>/package.nix`, HTTP 200 + `meta.platforms` checked).

Already installed on Zakkart (`modules/darwin/apps.nix`, `homebrew.nix`): Discord, iina,
moonlight-qt, mos, Obsidian, qbittorrent, Raycast, Telegram, UTM, Zed, Ghostty (wrapped);
CLI: bat, btop, claude-code, fd, gh, ripgrep, kubectl, helm, hcloud, imagemagick, etc.;
Bitwarden (MAS), NetBird (cask, own tap), Actual (cask). Categories obviously irrelevant
to this owner (Audio, Games, Streaming, Wallpaper, Screensaver, Cryptocurrency, most of
Mail/Social/Music) were skimmed and skipped.

## Candidates

### Window management

**Rectangle** — keyboard-driven window snapping (Spectacle successor).
https://github.com/rxhanson/Rectangle
Sourcing: **nixpkgs** (`by-name/re/rectangle`, `platforms = darwin`, verified 200).
Why: exactly the "keyboard-driven, low maintenance" fit — no daemon, no SIP dance, config
is a plist. Closest single-window analog to what he already gets from Hyprland's binds.
**Verdict: ADOPT.**

**yabai** — binary-space-partitioning tiling window manager.
https://github.com/koekeishiya/yabai
Sourcing: **nixpkgs** (`by-name/ya/yabai`, darwin, verified 200).
Why: true tiling, closer to Hyprland's model than Rectangle's snap-to-zone. Caveat: full
functionality (space-changing without animation, unmanaged windows) needs partially
disabling SIP and a signed scripting-addition injected into Dock.app — that's exactly the
kind of fragile, hand-run, non-declarative step ADR-0010 already works to avoid for
simpler things. Rectangle covers the 90% case with none of that.
**Verdict: TRY** only if Rectangle's zone-snapping genuinely feels insufficient; otherwise skip.

**AltTab** — Windows-style app/window switcher (macOS's own Cmd-Tab only shows apps, not windows).
https://github.com/lwouis/alt-tab-macos
Sourcing: **nixpkgs** (`by-name/al/alt-tab-macos`, darwin, verified 200).
Why: genuine gap in default macOS behavior for someone who thinks in windows, not apps.
**Verdict: TRY.**

**Hammerspoon** — Lua desktop automation framework.
https://github.com/Hammerspoon/hammerspoon
Sourcing: **cask only** — nixpkgs `by-name/ha/hammerspoon` returns 404 (not packaged for
darwin); cask exists (verified 200) → would need an ADR-0009 exception.
Why: powerful, but it's a general scripting platform, not a point solution — the "TRY"
candidates above (Rectangle, AltTab) already solve the concrete problems Hammerspoon would
otherwise be scripted to solve, with far less ongoing maintenance.
**Verdict: SKIP** — no problem here it uniquely solves; would trade a maintained nixpkgs
package for a hand-written Lua config.

### Keyboard / input

**Karabiner-Elements** — full keyboard remapping engine.
https://github.com/pqrs-org/Karabiner-Elements
Sourcing: **nixpkgs** (`by-name/ka/karabiner-elements`, darwin, verified 200).
Why: standard tool for anyone who wants Mac keyboard layouts (e.g. Caps→Ctrl/Esc,
cross-platform modifier parity with the NixOS boxes) done declarative-adjacent (its own
config is JSON, versionable).
**Verdict: ADOPT.**

### Displays

**MonitorControl** — control external-monitor brightness/volume via native keys or menu bar.
https://github.com/MonitorControl/MonitorControl
Sourcing: **nixpkgs** (`by-name/mo/monitorcontrol`, darwin, verified 200).
Why: MacBooks famously can't control non-Apple external display brightness with the
keyboard; this is the standard fix and needs zero ongoing care.
**Verdict: ADOPT.**

**Lunar** — adaptive/scheduled external-display brightness.
https://github.com/alin23/lunar
Sourcing: **nixpkgs** (`by-name/lu/lunar`, `aarch64-darwin`, verified 200).
Why: overlaps MonitorControl; Lunar adds automatic adaptive brightness curves, which is a
nice-to-have, not a gap.
**Verdict: SKIP** — MonitorControl alone covers the actual need.

### Menu bar management / system monitoring

**Ice** — menu bar item manager (hide/show icons, spacing).
https://github.com/jordanbaird/Ice
Sourcing: **nixpkgs** (`by-name/ic/ice-bar`, darwin, verified 200).
Why: with Raycast + Karabiner + MonitorControl + Stats all wanting menu bar space, a menu
bar manager stops icon crowding. Free, actively maintained successor to Bartender.
**Verdict: TRY.**

**Stats** — CPU/RAM/disk/network/battery menu bar monitor.
https://github.com/exelban/stats
Sourcing: **nixpkgs** (`by-name/st/stats`, darwin, verified 200).
Why: he already has `btop` for a terminal deep-dive; Stats is for glanceable menu-bar
numbers without opening a terminal. Genuinely additive, not redundant with btop.
**Verdict: TRY.**

**SwiftBar** — run arbitrary scripts as menu bar plugins (xbar-compatible).
https://github.com/swiftbar/SwiftBar
Sourcing: **nixpkgs** (`by-name/sw/swiftbar`, darwin, verified 200).
Why: nice for a Kubernetes-context or CI-status menubar plugin, but it's an empty
platform until he writes scripts for it — no concrete win today.
**Verdict: SKIP** (revisit if a specific "I want X in my menu bar" need shows up).

### Security / networking

**LuLu** — outbound-connection firewall (objective-see).
https://github.com/objective-see/LuLu
Sourcing: **nixpkgs** (`by-name/lu/lulu`, darwin, verified 200).
Why: DevSecOps background makes an open-source, auditable outbound firewall a natural fit
— visibility into what's phoning home matters more to this owner than to most.
**Verdict: TRY.**

**Wireshark** — protocol analyzer.
https://gitlab.com/wireshark/wireshark
Sourcing: **nixpkgs** (`by-name/wi/wireshark`, `platforms = linux ++ darwin`, verified 200).
Why: already the industry-standard tool for the kind of network debugging a DevSecOps
engineer occasionally needs (NetBird tunnel troubleshooting, k8s CNI issues reproduced
locally). Heavyweight to install "just in case" but trivial to add/remove given it's a
plain nixpkgs package.
**Verdict: TRY** — add only when a concrete need comes up; not default-on.

**Cryptomator** — client-side encryption for cloud-synced folders.
https://github.com/cryptomator/cryptomator
Sourcing: **cask** — nixpkgs `by-name/cr/cryptomator` exists but is `platforms =
["x86_64-linux"]` only (no darwin build); cask token `cryptomator` verified 200 → would
need an ADR-0009 exception.
Why: relevant if he syncs anything through a non-E2E cloud provider, but nothing in the
current setup (NetBird, self-hosted fleet) suggests third-party cloud sync is in play.
**Verdict: SKIP** unless a concrete cloud-sync-privacy need exists — flag as a cask
exception candidate if it does.

**KeePassXC** — offline password manager / KeePass client.
https://github.com/keepassxreboot/keepassxc
Sourcing: **nixpkgs** (`by-name/ke/keepassxc`, `platforms = linux ++ darwin`, verified 200).
Why: he already runs Bitwarden as the MAS-sandboxed build (ADR-0009 rationale explicitly
covers this). Adding a second password manager is pure redundancy.
**Verdict: SKIP** — Bitwarden already covers this need.

### Clipboard

**CopyQ** — advanced clipboard manager with history/scripting.
https://github.com/hluk/CopyQ
Sourcing: **cask only** — nixpkgs `by-name/co/copyq` is `platforms = linux` (no darwin
build); cask exists (verified 200) → ADR-0009 exception needed.
Why: Raycast (already installed) ships its own clipboard-history extension covering the
same use case natively, with no extra process or exception.
**Verdict: SKIP** — Raycast already does this.

### Databases / API tooling

**Beekeeper Studio** — SQL client (Postgres/MySQL/SQLite/Redshift/etc.), SQLite-storage,
no telemetry-by-default.
https://github.com/beekeeper-studio/beekeeper-studio
Sourcing: **nixpkgs** (`by-name/be/beekeeper-studio`, darwin, verified 200).
Why: for a Kubernetes/Helm engineer who occasionally needs to poke at an app's database
(Postgres for Actual/self-hosted apps, etc.), a lightweight open-source multi-engine GUI
client beats hand-rolling `psql`/`mysql` one-liners for exploratory work.
**Verdict: ADOPT.**

**DBeaver** (`dbeaver-bin`) — heavier, Java-based, broader-engine SQL client.
https://github.com/dbeaver/dbeaver
Sourcing: **nixpkgs** (`by-name/db/dbeaver-bin`, darwin, verified 200).
Why: functionally overlaps Beekeeper Studio; DBeaver's edge is exotic-engine support and
ER diagramming, at the cost of a much heavier JVM footprint and busier UI.
**Verdict: SKIP** — redundant with Beekeeper Studio for this owner's likely engines
(Postgres/SQLite/MySQL).

**Insomnia** — REST/GraphQL API client.
https://github.com/Kong/insomnia
Sourcing: **nixpkgs** (`by-name/in/insomnia`, darwin, verified 200).
Why: a keyboard-driven, terminal-centric engineer with `curl`, `httpie`-equivalents, and
`gh` already at hand gets little from a GUI REST client — this is the "GUI apps are noise"
case the brief calls out.
**Verdict: SKIP** — CLI tooling already covers this well.

**HTTP Toolkit** — HTTP(S) intercept/debug/mock proxy.
https://github.com/httptoolkit/httptoolkit-desktop
Sourcing: **nixpkgs** (`by-name/ht/httptoolkit`, built on `electron_41`, darwin build
present in nixpkgs — verified 200; not independently platform-restricted beyond
Electron's own darwin support).
Why: closer to `mitmproxy` (CLI, scriptable) territory than to a GUI he'd reach for daily;
useful occasionally but not a default-on tool.
**Verdict: SKIP** — niche; revisit only if a concrete intercept-debugging need arises.

### Calendar / meetings

**MeetingBar** — menu bar view of upcoming calendar meetings with one-click join.
https://github.com/leits/MeetingBar
Sourcing: **nixpkgs** (`by-name/me/meetingbar`, `aarch64-darwin`, verified 200).
Why: genuinely useful if he's in enough Teams/Zoom calls to want a menu-bar countdown +
join button instead of digging through Calendar.app.
**Verdict: TRY.**

### CLI (cross-cutting, not GUI)

**zoxide** — frecency-based smarter `cd`.
https://github.com/ajeetdsouza/zoxide
Sourcing: **nixpkgs** (`by-name/zo/zoxide`; no `meta.platforms` restriction — builds
everywhere, standard cross-platform Rust CLI, verified 200).
Why: not currently in `modules/darwin/apps.nix`'s CLI list despite `fd`/`ripgrep`/`bat`
already being there — an easy, zero-maintenance companion to that toolchain, useful on
both Zakkart and the NixOS fleet.
**Verdict: ADOPT.**

## Top 8 worth installing (ranked)

All are plain **nixpkgs** additions to `modules/darwin/apps.nix` — none of these require
an ADR-0009 Homebrew exception.

1. **Rectangle** — window snapping, zero maintenance, closest analog to Hyprland binds.
2. **zoxide** — trivial CLI addition, pairs with the fd/ripgrep/bat already installed.
3. **Karabiner-Elements** — keyboard remapping, standard tool for this use case.
4. **MonitorControl** — fixes the real external-display brightness gap on MacBooks.
5. **Beekeeper Studio** — lightweight multi-engine SQL client for occasional DB poking.
6. **LuLu** — auditable outbound firewall, fits the DevSecOps instinct for visibility.
7. **AltTab** — window-level Cmd-Tab, fixes a real macOS default-behavior gap.
8. **Stats** — glanceable menu-bar system monitor, additive to (not redundant with) btop.

Nothing in the top 8 needs a cask exception. Two TRY-tier items would, if he later wants
them: **Hammerspoon** (cask only, 404 in nixpkgs) and **Cryptomator** (cask only — nixpkgs
package exists but is Linux-only). Everything else marked SKIP is either genuinely
redundant with what's already installed (KeePassXC vs. Bitwarden, CopyQ vs. Raycast,
DBeaver/Insomnia vs. Beekeeper Studio/CLI tools) or a "GUI noise" case where the terminal
workflow he already has is the better tool.
