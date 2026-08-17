# Game streaming host research: Sunshine vs alternatives (artemis → zakkart)

Researched 2026-08-13 for the artemis remote-gaming conversion. Host: NixOS,
AMD dGPU (VAAPI), Hyprland/Wayland, headless (EDID dummy plug). Client:
Moonlight on macOS, over the NetBird mesh.

## Decision: Sunshine + moonlight-qt

- Steam Remote Play misbehaves when a WireGuard-style mesh interface is
  present on the host (Steam's discovery/relay stack gets confused —
  tailscale/tailscale#4320 documents the class of problem). Sunshine uses
  explicit ports and works predictably through a routed tunnel.
- macOS client: moonlight-qt (in nixpkgs, `platforms.all`) with VideoToolbox
  hardware decode for H.264/HEVC. AV1 decode is effectively software as of
  2026 — stream HEVC.

## Sunshine on NixOS

`services.sunshine` (nixos/modules/services/networking/sunshine.nix):
`enable`, `package`, `openFirewall`, `capSysAdmin`, `autoStart`, `settings`
(keyValue → sunshine.conf; setting it disables web-UI config), `applications`
(apps.json). Runs as a **systemd user unit bound to
`graphical-session.target`** — it captures an existing session, it does not
replace one. `capSysAdmin` is applied via `security.wrappers` (re-applied on
rebuild, unlike manual setcap).

Gotchas found:
- Fully headless Hyprland virtual output (`hyprctl output create headless`) +
  Sunshine is reported broken (LizardByte/Sunshine#2955, #4197). Working
  pattern: real monitor or EDID dummy plug.
- Standalone gamescope session (gamescope as DRM master) → Moonlight RTSP
  timeout (LizardByte/Sunshine#1928). Run gamescope **nested** inside the
  compositor instead.
- AMD on Linux encodes via VAAPI only (no AMF). nixpkgs has a recurring
  history of the sunshine derivation losing its VAAPI runtime deps
  (nixpkgs#271182, #305891, #343169) — verify the encoder list in Sunshine's
  log after every major bump.
- KMS capture reads the physical framebuffer: keep the output at scale 1 or
  the encode grabs the wrong region.
- Audio: as a user unit it inherits the user's PipeWire session and captures
  the default sink monitor; no bridging needed.

## Apollo (Sunshine fork) — rejected for now

- Its headline feature (auto virtual display matched to client resolution) is
  **Windows-only** (proprietary SudoVDA driver). Maintainer stated Linux
  support is effectively not coming to this codebase (issue #1466); the one
  experimental Linux PR (#1477) is unmerged and untested on Hyprland.
- On Linux, Apollo is upstream Sunshine's capture/encode code — no functional
  gain — and it is not in nixpkgs (community flake archived 2025-12).
- Client parity needs the Artemis client (Android-only); stock moonlight-qt
  works but loses the Apollo-specific extensions. No maintained macOS client.
- Maintenance: no release in ~11 months; maintainer says the codebase is done
  receiving investment pending an unscheduled rewrite (issue #1512).

Revisit if Apollo (or the MrOz59/Hermes fork's Hermes-KMS virtual display —
young, not in nixpkgs, unconfirmed on Hyprland) ships working per-client
virtual displays on Linux.
