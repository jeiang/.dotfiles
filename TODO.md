# Things I want to do for cornn flaek

## Quick & Easy (do whenever)

- [ ] Hyprpicker

## Bugs to Fix

- [ ] Eww bar gets closed when monitor is attached/detached
- [ ] After clicking the app launcher button on eww bar, subsequent left clicks anywhere on the bar will open the app
      launcher, instead of the normal action
  - Workaround: right click on the bar and normal state is restored

## High Priority

- [ ] Clipboard manager
- [ ] [sway osd](https://github.com/ErikReider/SwayOSD) found this, but idk about theming
- [ ] [Waylock](https://github.com/ifreund/waylock)
- [ ] [Wayprompt](https://git.sr.ht/~leon_plickat/wayprompt) perhaps use for pinentry?
- [ ] module for [zram](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/config/zram.nix), edit swap to be
      host-agnostic as well (i.e use labels) & make it priority 10 (so zram swap will be 5 > 10 used before hardware swap)
- [ ] Using base16.nix (like done in tofi), expose stylix colors to other apps
  - [ ] Theme Eww
  - [ ] Theme Hyprland

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
    - [ ] See [this wiki article](https://wiki.hyprland.org/FAQ/#how-do-i-move-my-favorite-workspaces-to-a-new-monitor-when-i-plug-it-in) about workspace switching
  - [ ] switches (hyprland switches, something something screen close)
- [ ] Bluetooth
- [ ] Hibernate and all that jazz
- [ ] power profiles daemon
- [ ] Eww misc
  - [ ] Scripts/Windows: Using a script + deflisten + windows, when state is changed, create a window for x seconds then
        close, or create a window which is closed after input.
    - [ ] Create an audio source switcher
    - [ ] Create a notifier that shows when a new audio source/sink is added
    - [ ] Brightness & Audio popup thing

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
- [x] App launcher, either bemenu (supported by stylix) or [tofi](https://github.com/philj56/tofi), but i would have to
      write a thing for it
  - Used tofi

## Abandoned

- [x] Switch to flameshot w/ grim
  - Tried, doesn't work
