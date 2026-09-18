# cornn flaek

[![Nix](https://img.shields.io/badge/built_with-nix-blueviolet?style=for-the-badge&logo=nixos)](https://nixos.org)

![cornn flaek](assets/cornn-flaek.jpg "Cornn Flaek")

Personal Nix flake for `artemis` (headless NixOS gaming and streaming box),
`zakkart` (nix-darwin MacBook), and the `legion-node1`..`legion-node4`
Hetzner service nodes.

![Network topology](docs/topology/network.svg "Network topology")

The networks connecting every host.

![Host topology](docs/topology/main.svg "Host topology")

The hosts, their services, and the connections between them.

- [`AGENTS.md`](AGENTS.md): layout, operation, and the decisions that
  constrain changes.
- [`docs/runbooks/`](docs/runbooks/): restore, binary cache, wallpaper, and
  zakkart bootstrap procedures.
- [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md): project name and source
  credits.
