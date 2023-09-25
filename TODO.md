# Things I want to do for cornn flaek

## Rebuild system away from digga

- [ ] Add overlays for packages so i can just do pkgs.whatever
  - [ ] Devenv
  - [ ] Hyprland (and derivative stuff)
  - [ ] Cachix
- [ ] Get back to a semi working state
- [ ] Get waybar (instead of eww)
- [ ] Figure out all the things i need waybar to do that it doesn't do natively
  - [ ] Do it in zig
- [ ] make a zig ipc thingy which parses things and automatically manages screens
- [ ] Hyprland external monitor main (laptop)
- [ ] Get back stylix
- [ ] Nvfetcher for fetch from github
  - [ ] Wezterm latest branch

## Quick & Easy (do whenever)

- [ ] Hyprpicker
- [ ] wthrr config declarative
- [ ] use bees (see [this](https://dataswamp.org/~solene/2022-08-16-btrfs-deduplication-with-bees.html) and
      [this](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/bees.nix)) for dedup btrfs

## High Priority

- [ ] [sway osd](https://github.com/ErikReider/SwayOSD) found this, but idk about theming
- [ ] [Waylock](https://github.com/ifreund/waylock)
- [ ] [Wayprompt](https://git.sr.ht/~leon_plickat/wayprompt) perhaps use for pinentry?
- [ ] module for [zram](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/zram.nix), edit swap to be
      host-agnostic as well (i.e use labels) & make it priority 10 (so zram swap will be 5 > 10 used before hardware swap)
- [ ] Using base16.nix (like done in tofi), expose stylix colors to other apps
  - [ ] Theme Hyprland
- [ ] Clean up system stuff & add a wsl config using [NixOS-WSL](https://github.com/nix-community/NixOS-WSL)

## Mid Priority

- [ ] Switch to config/opts model, or some way to indicate when a program is active (so that dependencies are not
      hard coded)
- [ ] Wezterm add additional fallback fonts (including font awesome 6)
  - [ ] [Use this to add custom fonts](https://www.adaltas.com/en/2022/03/29/nix-package-creation-install-font/)
- [ ] [Swayidle](https://github.com/swaywm/swayidle/issues/129)
- [ ] Better Hyprland conf
  - [ ] Transparency
  - [ ] More useful keybinds
  - [ ] Sleep on close screen
  - [x] Numlock remembering
  - [ ] Better screen workspaces (e.g. screen 1 has 1 - 5, screen 2 has 6 - 10 )
    - [ ] See
          [this wiki article](https://wiki.hyprland.org/FAQ/#how-do-i-move-my-favorite-workspaces-to-a-new-monitor-when-i-plug-it-in)
          about workspace switching
      - [ ] Zig???
  - [ ] switches (hyprland switches, something something screen close)
- [ ] Bluetooth
- [ ] Hibernate and all that jazz
- [ ] power profiles daemon

## Low Priority

- [ ] Make desktop files for programs which have guis
- [ ] Fish history editor (based on [this blog post](https://jordanelver.co.uk/blog/2020/05/29/history-deleting-helper-for-fish-shell/))
  - [ ] make it multiline (and use exact)
- [ ] Anything which uses fetchFromGitHub etc, should be moved to nvfetcher.toml
- [ ] Create some sort of minimal submodule to generate a string for hyprland conf (especially shortcuts & exec-once)
- [ ] additional styling for mako
- [ ] fish plugins
- [ ] Firefox: Add addons such as `tabs2txt` & `Image Seach Options` using [Mozilla Add-ons to Nix].
- [ ] SSDM theme: make an SDDM module for stylix? See [instructions on GitHub] and [this SDDM theme].
  - [ ] Automatically generate?
- [ ] Impermanence: Get it working less jankily??
- [ ] Agenix: GPG Private Keys?
- [ ] Spotify?

## In Progress

## Done ✓

- [x] Basic Impermanence
- [x] Hyprland (Basic)
- [x] Stylix
- [x] Plymouth
- [x] Firefox & Other Apps
- [x] App launcher, either bemenu (supported by stylix) or [tofi](https://github.com/philj56/tofi), but i would have to
      write a thing for it
  - Used tofi

## Abandoned

- [x] Switch to flameshot w/ grim
  - Tried, doesn't work
