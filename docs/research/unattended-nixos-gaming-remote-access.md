# Unattended NixOS gaming/remote-access host — research notes

Scope: Hyprland + greetd/tuigreet, impermanence (wipe-on-boot), no disk encryption,
AMD GPU, at-home box reached only over WireGuard/NetBird, no one at the keyboard.

Primary sources cited inline. Anything sourced from a blog/forum/Discourse/GitHub
issue thread is explicitly labeled **community report**, not spec.

---

## 1. Auto-login and immediate lock

**`initial_session` vs `default_session` (greetd's own config, not NixOS wiki):**
Per greetd's own man page (`greetd(5)`):

> "The default session is restarted every time a user session exits."
> "Auto-login can be achieved by configuring an initial session, which takes the
> place of the default session on the very first start. The default session will
> be started once the initial session exits."

So `default_session` = the greeter, relaunched forever on every logout.
`initial_session` = runs once, only on greetd's first start, as the given `user`;
once it exits, greetd falls back to `default_session` for all subsequent logins.
This is greetd's built-in auto-login mechanism — there's no separate "auto-login
flag," you just point `initial_session.command` at your compositor and set
`initial_session.user`.
Source: https://man.sr.ht/~kennylevinsen/greetd/ (greetd(5) config docs, also
mirrored at https://man.archlinux.org/man/greetd.5.en and the Debian manpage).

**`services.displayManager.autoLogin` (unified NixOS option):** confirmed current
and defined in `nixos/modules/services/display-managers/default.nix`:

```nix
autoLogin.enable = lib.mkOption {
  type = lib.types.bool;
  default = config.user != null;
  description = "Automatically log in as ${options.user}.";
};
autoLogin.user = lib.mkOption {
  type = with lib.types; nullOr str;
  default = null;
  description = "User to be used for the automatic login.";
};
```
Source: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/display-managers/default.nix

This is the modern, DM-agnostic replacement for the old per-manager options
(`services.xserver.displayManager.lightdm.autoLogin.*`,
`services.xserver.displayManager.sddm.autoLogin.*`, etc.), which are now
`mkRenamedOptionModule`-redirected or deprecated per the same module tree. It is
consumed by the greetd/SDDM/LightDM backends to populate their own auto-login
config (e.g. greetd's `initial_session`) — **for greetd specifically, most
NixOS configs still set `services.greetd.settings.initial_session` directly**,
since greetd's own module doesn't wire itself through
`displayManager.autoLogin` the way SDDM/LightDM do. Verify against your channel's
`services/display-managers/default.nix` before relying on the unified option with
greetd; the greetd module (`nixos/modules/services/greetd.nix`) primarily exposes
raw `settings.*`.

**Security considerations, no disk encryption, physical-access threat model:**
With impermanence + no LUKS, physical possession of the box gives an attacker
the ability to boot alternate media and read anything on persisted state anyway —
auto-login on the console changes little against that threat model (someone with
a screwdriver already owns the disk). Auto-login *does* matter against
"someone walks up and the screen is sitting unlocked" — i.e., a passer-by/guest
threat, not a boot-media threat. That's the case the immediate-lock pattern
below defends.

**Auto-login + immediate lock pattern:** there is no `services.hyprlock` NixOS
module — hyprlock ships as a `programs.hyprlock` module:

```nix
programs.hyprlock.enable  # nixos/modules/programs/wayland/hyprlock.nix
```
It adds hyprlock to `environment.systemPackages` and sets up
`security.pam.services.hyprlock` for PAM auth (otherwise hyprlock falls back to
`su`). It does **not** auto-start hyprlock — that's a Hyprland-config concern.
Source: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/programs/wayland/hyprlock.nix

The community pattern (**community report**, no official "recommended" doc from
Hyprland) is: `exec-once = hyprlock` in `hyprland.conf`, run at Hyprland start
right after auto-login lands you in the session, so the compositor is locked
before anything else initializes. Some setups chain
`exec-once = hyprlock || hyprctl dispatch exit` so a hyprlock crash doesn't leave
an unlocked session. `services.hypridle` (separate module,
`nixos/modules/services/hypridle.nix`-equivalent via `programs.hypridle` /
home-manager) is the idle-then-lock half; for "lock immediately on start" you
skip idle entirely and just exec hyprlock. There is a documented gap: a short
window between compositor start and hyprlock actually grabbing the session is
inherent to this pattern (raised in Hyprland/hyprlock issue trackers), acceptable
under a physical-access (not remote-network) threat model but not a hard
guarantee. Source (community): GitHub thesleepingsage/hypr-login,
hyprwm/hyprlock#564, hyprwm/Hyprland#5832.

---

## 2. Gaming/streaming host: compositor session vs headless

**Sunshine's own NixOS module runs as a systemd *user* unit bound to a graphical
session**, not headless-by-design:

```nix
systemd.user.services.sunshine = {
  after = [ "graphical-session.target" ];
  wants = [ "graphical-session.target" ];
  partOf = [ "graphical-session.target" ];
  wantedBy = lib.mkIf cfg.autoStart [ "graphical-session.target" ];
};
```
Source: `nixos/modules/services/networking/sunshine.nix` (module path per
nixpkgs PR #294641, "nixos/sunshine: init"; content verified via raw fetch of
`nixos-unstable`). So out of the box, Sunshine on NixOS assumes there *is* a
running graphical session to attach to (i.e. Hyprland via greetd auto-login),
not a truly display-less session.

**Sunshine's own capture backends** (LizardByte docs,
https://docs.lizardbyte.dev/projects/sunshine/latest/): three paths on Linux —
`wlr-export-dmabuf` (wlroots compositors, including Hyprland), the
xdg-desktop-portal PipeWire screencast (GNOME/KDE/anything with a portal), and
KMS (reads frames straight off the kernel modesetting interface, bypassing the
compositor; requires `cap_sys_admin`, i.e. NixOS's
`services.sunshine.capSysAdmin = true`).

**Real-world pattern for "no monitor attached" (community reports, not an
official recipe):** people either (a) run a real Hyprland session behind
auto-login with a **dummy HDMI plug / EDID-emulation dongle** so the GPU still
has a "real" output to drive, or (b) try Hyprland's virtual/headless output
(`hyprctl output create headless`) with Sunshine capturing that output. Path (b)
is reported as currently broken/unsupported: "the current headless
implementation of Hyprland is unsupported by Sunshine for some reason since a
few versions ago," and a separate open Sunshine issue confirms
"Can't stream a headless monitor created with Hyprland." Sources (community):
- https://catwithcode.moe/Blog/2025.03.21_Sunshine_Remote_Headless_Hyprland/Sunshine_Remote_Headless_Hyprland.html
- https://github.com/LizardByte/Sunshine/issues/2955 ("Can't stream a headless monitor created with Hyprland")
- https://github.com/LizardByte/Sunshine/issues/4197 ("Doesn't work with Hyprland virtual display")

**gamescope `--backend headless`:** gamescope itself documents a headless
backend ("use headless backend (no window, no DRM output)"), intended for
running Steam on a display-less box and streaming out via Steam Link/VNC/Sunshine
on top. Source: gamescope README / `--help` text,
https://github.com/ValveSoftware/gamescope/blob/master/README.md. This is the
gamescope CLI flag, not a NixOS module option — the nixpkgs `programs.gamescope`
module (`nixos/modules/programs/gamescope.nix`) only wraps the binary
(`capSysNice`, `enableWsi`, `args`, `env`); it doesn't have a first-class
"headless session" option, you'd invoke `gamescope --backend headless -- sunshine`
(or similar) yourself as the greetd `initial_session` command.

**Container-based alternative (Games on Whales / Wolf):** Wolf explicitly targets
this use case — "on-demand creation of virtual desktops with full support for
any resolution/FPS without the need for a monitor or a dummy plug" — using a
custom Smithay-based Wayland compositor (`gst-wayland-display`) plus gamescope
for XWayland/Steam and `inputtino` for virtual input. This is a genuinely
headless design (no reliance on a real or emulated GPU output) but it's a
Docker-first project, not a native NixOS module; you'd run it as an OCI
container. Source: https://github.com/games-on-whales/wolf,
https://games-on-whales.github.io/wolf/stable/dev/how-it-works.html.

**Bottom line for 2025-2026 NixOS gaming hosts:** the dominant, best-supported
pattern is still auto-login into a real Hyprland session (dummy plug if no
monitor is physically connected) with Sunshine attached to that session via
`wlr-export-dmabuf` or KMS — not a headless compositor output. Fully headless
(no EDID/dummy plug at all) Sunshine+Hyprland is reported broken as of the 2025
issues above; Wolf is the only genuinely headless option found, at the cost of
running outside the native NixOS module ecosystem.

---

## 3. Recovery from hangs: watchdogs and AMD GPU reset

**systemd watchdog options have been renamed in current nixpkgs.** The old
`systemd.watchdog.*` namespace is gone; nixpkgs now exposes these under the
generic settings namespace via `mkRenamedOptionModule`:

- `systemd.watchdog.device`      → `systemd.settings.Manager.WatchdogDevice`
- `systemd.watchdog.runtimeTime` → `systemd.settings.Manager.RuntimeWatchdogSec`
- `systemd.watchdog.rebootTime`  → `systemd.settings.Manager.RebootWatchdogSec`
- `systemd.watchdog.kexecTime`   → `systemd.settings.Manager.KExecWatchdogSec`

Source: `nixos/modules/system/boot/systemd.nix` on `nixos-unstable`
(renamed-option redirects verified via raw fetch;
https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd.nix).
**Check your channel** — if you're pinned to an older release the pre-rename
`systemd.watchdog.runtimeTime` / `.rebootTime` / `.device` names may still be
correct; the rename is recent enough that release-branch behavior varies.

Underlying semantics (from systemd's own `systemd-system.conf(5)`, upstream, via
the Debian manpage mirror): `RuntimeWatchdogSec=` "configures the hardware
watchdog at runtime... the watchdog hardware (`/dev/watchdog0` or the path
specified with `WatchdogDevice=`) will be programmed to automatically reboot the
system if it is not contacted within the specified timeout interval. **The
system manager will ensure to contact it at least once in half the specified
timeout interval.**" Default is off (`0`); `ShutdownWatchdogSec=` defaults to
10 min. Source: `systemd-system.conf(5)`, https://manpages.debian.org/bookworm/systemd/systemd-system.conf.5.en.html.

**This matters for the D-state question:** the systemd runtime watchdog is
petted by PID 1 (the system manager), not by any check of GPU/session health.
As long as systemd's own event loop is alive — which it typically is even when
a GPU-bound process is wedged in D-state — the watchdog keeps getting petted and
**will not fire** just because a game/compositor process is stuck. A software
watchdog alone is not sufficient against an amdgpu wedge unless the wedge takes
the whole kernel scheduler down with it (rare; more common is one process/driver
subsystem stuck while the rest of the machine, including PID 1, keeps running).

**Kernel hung-task detector is the piece that actually watches for D-state
hangs.** From `Documentation/admin-guide/sysctl/kernel.rst` (upstream Linux,
verbatim):
- `hung_task_timeout_secs`: "When a task in D state did not get scheduled for
  more than this value report a warning... 0 means infinite timeout, no
  checking is done." Default 120s.
- `hung_task_panic`: "When set to a non-zero value, a kernel panic will be
  triggered if the number of hung tasks found during a single scan reaches this
  value." Default 0 (warn only).

Source: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/sysctl/kernel.rst.
`hung_task_panic` (via a NixOS `boot.kernel.sysctl."kernel.hung_task_panic" = 1;`
setting) plus `kernel.panic` set to a positive number of seconds — from the same
doc: "if positive, the kernel will reboot after the corresponding number of
seconds... When you use the software watchdog, the recommended setting is 60" —
is the combination that actually turns a wedged D-state task into an automatic
reboot, because khungtaskd runs as an independent kernel thread and doesn't
depend on the wedged subsystem being responsive. `panic_on_oops=1` additionally
makes an amdgpu driver oops (rather than a silent hang) also trigger the same
panic→reboot path. Sources: same kernel.rst; `panic`, `panic_on_oops` sections.

**AMD GPU reset/recovery kernel params** (`docs.kernel.org/gpu/amdgpu/module-parameters.html`,
official amdgpu driver docs):
- `amdgpu.gpu_recovery`: "Set to enable GPU recovery mechanism (1 = enable,
  0 = disable). The default is -1 (auto, disabled except SRIOV)."
- `amdgpu.lockup_timeout`: "Set GPU scheduler timeout value in ms" (per-engine
  GFX/Compute/SDMA/Video variants supported); default 2000ms.
- `amdgpu.reset_method`: "GPU reset method (-1 = auto (default), 0 = legacy,
  1 = mode0, 2 = mode1, 3 = mode2, 4 = baco)."

Source: https://docs.kernel.org/gpu/amdgpu/module-parameters.html. In practice
(**community reports**, Arch/Framework/CachyOS forums, 2025), amdgpu suspend/
resume hangs and MES-timeout hangs are common enough on recent AMD parts that
`gpu_recovery=1` is frequently set explicitly rather than relying on `-1` auto
behavior, but recovery success is inconsistent — several reports describe GPU
resets that themselves fail and leave the box needing a hard power cycle.
Sources (community): https://community.frame.work/t/amd-gpu-mes-timeouts-causing-system-hangs-on-framework-laptop-13-amd-ai-300-series/71364,
https://bbs.archlinux.org/viewtopic.php?id=307650.

**Practical verdict:** a purely software (systemd `RuntimeWatchdogSec`) watchdog
is not reliable against an amdgpu D-state wedge, because PID 1 usually stays
alive and keeps petting it regardless. What's actually effective is the
combination of (1) `hung_task_panic` + `kernel.panic` (kernel-level, independent
of the wedged subsystem, turns any true D-state hang into a panic→reboot) and
(2) `systemd.settings.Manager.WatchdogDevice = "/dev/watchdog"` with
`RebootWatchdogSec` set, so that if the panic path *itself* can't complete a
clean reboot (e.g., the panic handler stalls), the **hardware** watchdog forces
a hard reset. A hardware watchdog device is the backstop for the case a software
path can't recover from; software-only (`RuntimeWatchdogSec` with no hardware
device, i.e. the systemd soft-watchdog fallback) only protects against total
scheduler death, which a single-process D-state hang usually isn't.

---

## 4. Unattended `nixos-rebuild`: `system.autoUpgrade` vs push-deploy

`system.autoUpgrade` (`nixos/modules/tasks/auto-upgrade.nix`) does support
flakes directly: `system.autoUpgrade.flake` takes a flake URI/path (e.g.
`inputs.self.outPath` or `git+ssh://...`), and `allowReboot` controls reboot
behavior — "the system will automatically reboot if the new generation contains
a different kernel, initrd or kernel modules" when `true`; otherwise it just
switches without rebooting. Source: `nixos/modules/tasks/auto-upgrade.nix`
(verified via raw fetch, `nixos-unstable`), corroborated by
https://wiki.nixos.org/wiki/Automatic_system_upgrades.

For a **private** git repo, `system.autoUpgrade` has no dedicated
credential/auth option — it shells out to `nixos-rebuild`/`nix` as root with
`HOME=/root`, so private-repo auth is whatever root's environment already
provides (an SSH deploy key in `/root/.ssh` for `git+ssh://` flake refs, or a
netrc/`extra-access-tokens` style Nix config for HTTPS+token refs). You have to
wire that up yourself; the module doesn't manage it.

**Verdict:** `system.autoUpgrade` is reasonable for this box specifically
*because* it's a pull model that needs no network path opened toward the
machine — it's already got outbound access to the private repo over the NetBird
mesh or a plain internet path, and a bad build just fails the timer rather than
bricking a remote deploy pipeline. The tradeoffs are: no built-in rollback
health-check (unlike deploy-rs, which SSHes back in after activation and
auto-rolls-back if the box goes unreachable — a real advantage on a
box you can't walk up to), and reboot timing on `allowReboot = true` is a plain
systemd timer, not gated on "is anyone gaming right now." For a home box with
impermanence and no one physically present, `autoUpgrade` with `allowReboot =
true`, a conservative `dates` window (e.g. 4am), and a deploy key scoped
read-only to the flake repo is sane; push-deploy tools (deploy-rs/colmena) earn
their complexity when you need the auto-rollback-on-unreachable safety net or
you're managing more than one host from a control machine, neither of which is
this scenario. Sources: `nixos/modules/tasks/auto-upgrade.nix`;
deploy-rs README (https://github.com/serokell/deploy-rs) for the
rollback-on-unreachable behavior claim.

---

## 5. Power: Wake-on-LAN, suspend, and the WireGuard broadcast problem

**Current option:** `networking.interfaces.<name>.wakeOnLan.enable` (boolean) and
`networking.interfaces.<name>.wakeOnLan.policy` (list of `"phy" | "unicast" |
"multicast" | "broadcast" | "arp" | "magic" | "secureon"`), declared in
`nixos/modules/tasks/network-interfaces.nix`. Source:
https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/tasks/network-interfaces.nix,
corroborated by the option-tracking pages at
https://mynixos.com/nixpkgs/option/networking.interfaces.%3Cname%3E.wakeOnLan.enable
and open nixpkgs issue #415213 (policy-not-working reports, i.e. verify actual
behavior with `ethtool` post-activation — a known rough edge, **community
report**).

**AMD GPU suspend/resume:** known-troublesome (**community reports**, not an
AMD spec document) — repeated 2025 reports of amdgpu failing to recover from
suspend, particularly VRAM-eviction-on-suspend races and "GPU resets repeatedly
failing after resume." A documented community workaround ("memreserver," 2020-2023)
runs as a pre-sleep systemd service to work around the VRAM eviction bug; a
kernel-side fix reportedly landed around 6.14. Sources:
https://nyanpasu64.gitlab.io/blog/amdgpu-sleep-wake-hang/,
https://bbs.archlinux.org/viewtopic.php?id=307650. Given this, and that the box
must be reachable unattended, **not suspending at all** (always-on) is the
lower-risk choice over relying on suspend/resume + WoL for an AMD gaming host.

**WireGuard and WoL — confirmed, this does not work across the mesh.**
WireGuard operates strictly at layer 3: it's a routed IP tunnel between peer
public keys/allowed-IP ranges, with no shared Ethernet broadcast domain spanning
the tunnel — this is inherent to WireGuard's "cryptokey routing" design
described in the official whitepaper (peers are identified and routed by IP,
not bridged at L2). Source: WireGuard whitepaper,
https://www.wireguard.com/papers/wireguard.pdf; official routing docs
https://www.wireguard.com/netns/ (routing/namespace model, L3 throughout, no
broadcast/multicast domain). A WoL magic packet is either an L2 Ethernet
broadcast or an L3 packet sent to the LAN's directed-broadcast address —
neither survives being routed through an L3 point-to-point tunnel to a peer
that isn't itself on that Ethernet segment, since there's no broadcast domain to
deliver it into on the far end. (Corroborating **community report** covering the
identical Wireguard-specific case: "for the purpose of WoL the two ends of the
Wireguard tunnel are in two different, not connected networks... the router just
drops it," https://forum.openwrt.org/t/how-can-i-make-the-wake-on-lan-wol-magic-packet-travel-from-the-vxlan-over-wireguard-to-the-local-network-on-the-other-end-of-the-vxlan/188693.)

**Real workarounds:**
1. Don't suspend the gaming host at all — sidesteps the problem entirely, at the
  cost of idle power draw. Given the AMD suspend/resume reliability concerns
  above, this is the recommended default for this box.
2. Keep a second, always-on low-power box on the same home LAN (a NAS, router,
  Pi, etc.) that's reachable over the NetBird mesh; SSH into *that* box and have
  it emit the L2 magic-packet broadcast locally onto the home LAN, where the
  gaming host actually is. This works because the magic packet only needs to
  survive an L2 broadcast, and that box is physically on the same segment.
3. A mesh-reachable smart plug (Kasa/Shelly/Zigbee-via-hub/etc.) for a hard
  power cycle as a last-resort fallback when the box is fully wedged and won't
  even respond to WoL — this is your recovery path for the "kernel really did
  panic but the watchdog didn't complete a clean reboot" case from section 3,
  not a normal-use pattern.

---

## 6. Remote desktop on wlroots/Hyprland: wayvnc, Sunshine, RustDesk

**wayvnc** — genuinely supports headless, no monitor/seat required. Per its own
FAQ (any1/wayvnc): run the wlroots compositor itself in headless mode
(`WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1` before starting sway/Hyprland),
then `WAYLAND_DISPLAY=wayland-1 wayvnc` attaches to that headless Wayland
session. wayvnc only supports wlroots-based compositors (explicitly *not*
GNOME/KDE/Weston) — Hyprland qualifies. By default it only accepts localhost
connections; you must explicitly configure it for LAN/mesh exposure with
authentication. Source: https://github.com/any1/wayvnc/blob/master/README.md,
https://github.com/any1/wayvnc/blob/master/FAQ.md. NixOS module:
`programs.wayvnc.enable`/`.package`, `nixos/modules/programs/wayland/wayvnc.nix`
— thin wrapper (installs the package, configures
`security.pam.services.wayvnc`), you still assemble the systemd unit and
headless-compositor invocation yourself.

**Sunshine's desktop-stream mode does *not* run headless out of the box** — see
section 2: the nixpkgs module binds it to `graphical-session.target` as a user
unit, and its wlroots/KMS capture paths both assume a real (or dummy-plugged)
GPU output exists. The LizardByte community itself frames it as
"Sunshine + moonlight ALMOST make for a viable VNC replacement" (GitHub
Discussion, LizardByte/Sunshine — **community report**, title reflects known
limitations, not full VNC-replacement parity) —
https://github.com/orgs/LizardByte/discussions/45.

**RustDesk:** the nixpkgs `services.rustdesk-server` module
(`signal`/`relay` suboptions, `openFirewall`) stands up only the *rendezvous/
relay* server — the piece that lets RustDesk clients find and connect through
each other; it does not itself capture or serve a desktop. Actual remote
control of the NixOS box needs the `rustdesk` client binary running as the
*controlled* side, which — like any desktop-capture tool — needs an active
graphical session to grab (X11 or a supported Wayland capture path), so it does
not solve headless-with-no-session either; self-hosting the relay only removes
your dependency on RustDesk's public rendezvous servers, it doesn't change the
capture-needs-a-session constraint. Source (option shape):
https://mynixos.com/nixpkgs/options/services.rustdesk-server.

**macOS client support:**
- **moonlight-qt**: official Apple Silicon (arm64) builds exist; Intel Mac
  users must build from source (per the moonlight-qt GitHub project page,
  https://github.com/moonlight-stream/moonlight-qt). Pairs with Sunshine.
- **Sunshine**: no native macOS *server* is the relevant point here (this box is
  the server), but macOS is a first-class Moonlight *client* target via
  moonlight-qt above.
- **RustDesk**: ships an official macOS client (rustdesk.com downloads/docs).
- **wayvnc**: it's a standard RFB/VNC server, so any macOS VNC client works —
  RealVNC Viewer, Screens, or built-in macOS Screen Sharing — subject to
  wayvnc's default localhost-only bind needing to be opened up and secured for
  remote (mesh) use. **Community reports** note some rough edges with
  RealVNC-vs-wayvnc keyboard-shortcut and mouse handling.

**Which actually work fully headless (no monitor/seat):** wayvnc, via a
headless-backend wlroots compositor — confirmed by upstream docs. Sunshine:
not out of the box (needs a dummy plug or a currently-broken Hyprland
headless-output path, section 2). RustDesk: same constraint as Sunshine — needs
a real capturable session on the controlled machine.

---

## Workarounds / gotchas (distilled from community reports)

- Hyprland `hyprctl output create headless` + Sunshine capture is currently
  reported broken/unsupported (LizardByte/Sunshine#2955, #4197) — use a dummy
  HDMI/EDID plug instead if you want Sunshine with no monitor physically
  connected.
- Sunshine's KMS capture path needs `capSysAdmin = true` in the NixOS module,
  which is reported to break `cap_sys_admin+p` propagation for other
  user-launched apps in some Hyprland setups — isolate Sunshine's environment
  from your normal session tooling if you hit this.
- `networking.interfaces.<name>.wakeOnLan.policy` has open reports of not
  actually taking effect as declared (nixpkgs#415213) — verify with `ethtool
  <iface>` after activation, don't trust the Nix config alone.
- AMD GPU suspend/resume is unreliable enough on recent hardware (2025 reports
  across Arch/CachyOS/Framework forums) that avoiding suspend entirely is safer
  than debugging amdgpu resume hangs on a box nobody can walk up to.
- WireGuard/NetBird WoL magic packets do not cross the mesh — this is a
  structural property of WireGuard's L3 routed-tunnel model, not a
  misconfiguration; don't spend time trying to "fix" it, use a same-LAN relay
  box or a smart plug instead.
- systemd's `RuntimeWatchdogSec` (petted by PID 1) will not detect a
  single-process amdgpu D-state wedge if PID 1 itself stays responsive — pair
  it with kernel `hung_task_panic` + `kernel.panic` (a positive seconds value)
  so a true D-state hang forces a panic→reboot independently of the wedged
  subsystem, and back both with a hardware `WatchdogDevice` as the last-resort
  hard reset.
- `systemd.watchdog.*` option names were renamed to
  `systemd.settings.Manager.*` in recent nixpkgs — check which shape your
  pinned channel expects before copying examples from older blog posts.
