# Dotfiles

Currently a backup of my NixOS config. Some things here are not set up all that well (still a novice).

Based on the following tutorials:
- [Wil Taylor Tutorials](https://linktr.ee/nixos): 
Used for the initial setup & some scripting.
- [mt-caret's blog post on btrfs w/ nixos](https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html): 
Used to setup my primary system using btrfs and have opt-in state. Encryption using LUKS was skipped as it caused issues with GRUB.
- [Misterio77's minimal starter config](https://github.com/Misterio77/nix-starter-configs): 
Used as a basis for setting up the flake. (As well as understanding how flakes work for system config.)
- [Impermanence](https://github.com/nix-community/impermanence):  
  Used to implement persistence for system files.
  
## TODO
- [ ] Implement Persistence for home.
- [ ] Add nix-autobahn.
- [ ] Get renpy games working.
- [ ] Get Rust Stuff working.
