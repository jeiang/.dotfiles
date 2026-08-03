{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # devenv
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # system management inputs
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    hjem.url = "github:feel-co/hjem";
    hjem.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # Determinate manages the Nix installation itself on Zakkart (see
    # docs/adr/0008); its own installer owns the daemon/upgrades, so this
    # flake only needs its nix-darwin module, not a separate Nix. Following
    # our nixpkgs here would be pointless anyway: `determinate-nixd` is a
    # prebuilt binary the module fetches, not something this flake builds.
    determinate.url = "github:DeterminateSystems/determinate";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # Homebrew itself and its taps: pinned as flake inputs so
    # `mutableTaps = false` (docs/adr/0009) has something to pin to instead
    # of `brew tap` mutating state at activation. None of these are flakes.
    homebrew-brew = {
      url = "github:Homebrew/brew";
      flake = false;
    };
    homebrew-core = {
      url = "github:Homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:Homebrew/homebrew-cask";
      flake = false;
    };
    can1357-tap = {
      url = "github:can1357/homebrew-tap";
      flake = false;
    };
    k06a-tap = {
      url = "github:k06a/homebrew-tap";
      flake = false;
    };
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    dms.url = "github:AvengeMedia/DankMaterialShell/stable";
    dms.inputs.nixpkgs.follows = "nixpkgs";
    dsearch.url = "github:AvengeMedia/danksearch";
    dsearch.inputs.nixpkgs.follows = "nixpkgs";

    # Packages
    website.url = "github:jeiang/website";
    website.inputs.nixpkgs.follows = "nixpkgs";
    # portfolio: plain stdenvNoCC static build with no external deps
    # beyond nixpkgs, so following our pin is safe.
    portfolio.url = "github:joshua-noel/portfolio";
    portfolio.inputs.nixpkgs.follows = "nixpkgs";
    # bill-splitter: plain stdenvNoCC static build ($out/dist) with no
    # external deps beyond nixpkgs, same reasoning as portfolio above.
    bill-splitter.url = "github:jeiang/bill-splitter";
    bill-splitter.inputs.nixpkgs.follows = "nixpkgs";
    # Deliberately not following our nixpkgs: attic-client is built with
    # attic's own nixpkgs pin and pushed to the Attic cache by jeiang/attic's
    # own CI. Following ours here would give attic-client a different
    # derivation (different rustc/deps) and thus a different store path than
    # what's actually cached, forcing a from-source rebuild in CI. CI also
    # installs the client from this input's locked rev (see
    # .github/workflows/ci.yml), so this lock is the single pin to bump.
    attic.url = "github:jeiang/attic";
    # Hermes agent (upstream NixOS module consumed directly by
    # modules/nixos/hermes/). Deliberately not following our nixpkgs: the
    # upstream flake carries a uv2nix-built Python environment tested
    # against its own pin; following ours would force a full rebuild of
    # that environment on every nixpkgs bump (same reasoning as attic
    # above).
    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.7.30";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
