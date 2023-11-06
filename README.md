# cornn flaek (my dotfiles)

[![Nix](https://img.shields.io/badge/built_with-nix-blueviolet?style=for-the-badge&logo=nixos)](https://nixos.org)

![cornn flaek](assets/cornn-flaek.jpg "Cornn Flaek")

This repository is home to the nix code that builds my systems. Currently just my laptop. Uses [this template] based on
[flake.parts].

## Why Nix?

Nix allows for easy to manage, collaborative, reproducible deployments. This means that once something is setup and
configured once, it works forever. If someone else shares their configuration, anyone can make use of it. Also, if it
breaks, its pretty quick and easy to get back to up and running.

## Why the name?

I saw a guy name his flake frosted flakes, and cornn flaek just popped into my head.

## Acknowledgements

I have used tutorials/configs from the below people (and maybe a few others which I have forgotten).

- [Wil Taylor]: I used his tutorials for my initial setup, and it got me into nix/NixOS.
- [mt-caret]: Used a tutorial from them for setting up an encrypted btrfs w/ NixOS & impermanence.
- [Mysterio77]: Used his flake configs before this, and fiddling with them helped me understand nix better. (Also clued
  me into btrfs wipe w/ systemd stage 1 through his personal flake.)
- [Lord Valen] & [Divnix]: Divnix for Digga (used to make this flake) and Lord Valen for the minimal flake config I used
  for this setup.
- [danth]: Stylix is amazing, and I hope it supports even more stuff.
- [hexa & kjhoerr]: kjhoerr asked a question for something I had wanted to do for a while (same partial tutorial too).
  hexa answered.
- [JavaCafe01]: I saw the frosted flakes and immediately thought `cornn flaek`.

<!-- Links -->

[danth]: https://github.com/danth
[divnix]: https://github.com/divnix
[flake.parts]: https://flake.parts/
[hexa & kjhoerr]: https://discourse.nixos.org/t/impermanence-vs-systemd-initrd-w-tpm-unlocking/25167/2
[javacafe01]: https://github.com/JavaCafe01/frostedflakes
[lord valen]: https://github.com/Lord-Valen
[mt-caret]: https://github.com/mt-caret
[mysterio77]: https://github.com/Misterio77
[this template]: https://zero-to-flakes.com/nixos-flake/templates
[wil taylor]: https://linktr.ee/nixos
