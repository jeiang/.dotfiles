# cornn flaek (my dotfiles)

[![Nix](https://img.shields.io/badge/built_with-nix-blueviolet?style=for-the-badge&logo=nixos)](https://nixos.org)
[![Digga](https://img.shields.io/badge/divnix-digga-blueviolet?style=for-the-badge&logo=nixos)](https://github.com/divnix/digga)

![cornn flaek](assets/cornn-flaek.jpg "Cornn Flaek")

This repository is home to the nix code that builds my systems. Currently just my laptop.

## Why Nix?

Nix allows for easy to manage, collaborative, reproducible deployments. This means that once something is setup and
configured once, it works forever. If someone else shares their configuration, anyone can make use of it. Also, if it
breaks, its pretty quick and easy to get back to up and running.

## Why the name?

I saw a guy name his flake frosted flakes, and cornn flaek just popped into my head.

## Acknowledgements

- [Wil Taylor]: I used his tutorials for my initial setup, and it got me into nix/NixOS.
- [mt-caret]: Used a tutorial from them for setting up an encrypted btrfs w/ NixOS & impermanence.
- [Misterio77]: Used his flake configs before this, and fiddling with them helped me understand nix better.
- [Lord Valen] & [Divnix]: Divnix for Digga (used to make this) and Lord Valen for the minimal flake config I used for this setup.
- [danth]: Stylix is amazing, and I hope it supports even more stuff.

## TODO

- Firefox: Add addons such as `tabs2txt` & `Image Seach Options` using [Mozilla Add-ons to Nix].
- SSDM theme: make an SDDM module for stylix? See [instructions on GitHub] and [this SDDM theme].
- Hyprland: make a hyprland module for stylix?
- Impermanence: Get it working less jankily??
- Agenix: GPG Private Keys?

<!-- Links -->

[Wil Taylor]: https://linktr.ee/nixos
[mt-caret]: https://github.com/mt-caret
[Mysterio77]: https://github.com/Misterio77
[Lord Valen]: https://github.com/Lord-Valen
[Divnix]: https://github.com/divnix
[danth]: https://github.com/danth
[Mozilla Add-ons to Nix]: https://git.sr.ht/~rycee/mozilla-addons-to-nix/
[instructions on GitHub]: https://github.com/MarianArlt/kde-plasma-chili/issues/1#issuecomment-614935624
[this SDDM theme]: https://github.com/michaelpj/nixos-config/blob/e5be6d0f0e431748c0a8c532f9776c14e67ed8c9/nixpkgs/pkgs/sddm-themes.nix
