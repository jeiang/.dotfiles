# Things to Do

## Backlog

### High Priority

- Set up Stylix

  - Use a library which exposes colors (such as base-16.nix) and manually theme programs not already supported

  - Programs to theme:

    - Hyprland

    - Mako (notifications)

- Add overlays

  - Add overlays for packages exposed by inputs

  - Add overlays dir using nvfetcher (like prior digga config)

  - Replace all references to fetchfromgithub with nvfetcher

- Set up an App Launcher

- Agenix:

  - Set up private GPG keys

- Hyprland Config:

  - Hyprpaper etc.

  - Transparency on some pages

  - Better Keybinds

### Low Priority

- Create a client for hyprland that listens to the IPC and manages events

- Set up Wezterm

  - Wezterm is currently broken on Hyprland

  - Add more fallback fonts

- Programs to set up/add

  - Hyprpicker

  - [Sway OSD](https://github.com/ErikReider/SwayOSD)

  - [Waylock](https://github.com/ifreund/waylock)

  - [Wayprompt](https://git.sr.ht/~leon_plickat/wayprompt)

  - [Swayidle](https://github.com/swaywm/swayidle/issues/129)

- Addtional Nix Configs

  - Bootstrap ISO

  - [WSL](https://github.com/nix-community/NixOS-WSL)

  - Laptop

- Reduce hard coded dependencies (i.e. detect if a config is enabled and enable custom features)

- Fish history editor (based on [this blog post](https://jordanelver.co.uk/blog/2020/05/29/history-deleting-helper-for-fish-shell/))

  - make it multiline (and use exact)

- Create Firefox Addons for other extensions

- Use [bees](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/bees.nix)) for BTRFS Deduplication

- Put the wthrr in to config

## Next Tasks

- Add waybar

- Implement automatic system sleep

- Create a lib folder

## In Progress

## Done

## Rejected
