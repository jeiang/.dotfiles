# Things I want to do for cornn flaek

High Priority is stuff I need to do before I can merge into main (i.e. everything "just works", if barely). Low priority
is nice to haves or misc improvements for later. Mid is the same as low, but I want it before low.

## Quick & Easy (do whenever)

- [ ] Switch to flameshot w/ grim
- [ ] Hyprpicker

## High Priority (i.e do now)

- [ ] Clipboard manager
- [ ] App launcher, either bemenu (supported by stylix) or [tofi](https://github.com/philj56/tofi), but i would have to
      write a thing for it
- [ ] [osd??](https://github.com/ErikReider/SwayOSD) found this, but idk about theming
- [ ] [Waylock](https://github.com/ifreund/waylock)
- [ ] [Wayprompt??](https://git.sr.ht/~leon_plickat/wayprompt) perhaps use for pinentry?
- [ ] module for [zram](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/zram.nix), edit swap to be
      host-agnostic as well (i.e use labels) & make it priority 10 (so zram swap will be 5 > 10 used before hardware swap)

## Mid Priority (Longer term??)

- [ ] Better Hyprland conf
  - [ ] Transparency
  - [ ] More useful keybinds
  - [ ] Sleep on close screen
- [ ] Bluetooth
- [ ] Hibernate and all that jazz
- [ ] power profiles daemon

## Low Priority (Longer Longer term)

- [ ] Anything which uses fetchFromGitHub etc, should be moved to nvfetcher.toml
- [ ] Create some sort of minimal submodule to generate a string for hyprland conf (especially shortcuts & exec-once)
- [ ] additional styling for mako
- [ ] fish plugins
- [ ] Firefox: Add addons such as `tabs2txt` & `Image Seach Options` using [Mozilla Add-ons to Nix].
- [ ] SSDM theme: make an SDDM module for stylix? See [instructions on GitHub] and [this SDDM theme].
- [ ] Hyprland: make a hyprland module for stylix?
- [ ] Impermanence: Get it working less jankily??
- [ ] Agenix: GPG Private Keys?

## In Progress

- [ ] Ewww

## Done ✓

- [x] Basic Impermanence
- [x] Hyprland (Basic)
- [x] Stylix
- [x] Plymouth
- [x] Firefox & Other Apps
