{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Determinate's `nix flake show` reads the schemas output; lib-only flake with no nixpkgs input to follow.
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";

    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    hjem.url = "github:feel-co/hjem";
    hjem.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # No follows: determinate-nixd is a prebuilt binary the module fetches, not something this flake builds.
    determinate.url = "github:DeterminateSystems/determinate";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    # Homebrew and its taps are pinned flake inputs so mutableTaps = false has something to pin to; none are flakes.
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
    netbird-tap = {
      url = "github:netbirdio/homebrew-tap";
      flake = false;
    };
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";

    website.url = "github:jeiang/website";
    website.inputs.nixpkgs.follows = "nixpkgs";
    portfolio.url = "github:joshua-noel/portfolio";
    portfolio.inputs.nixpkgs.follows = "nixpkgs";
    bill-splitter.url = "github:jeiang/bill-splitter";
    bill-splitter.inputs.nixpkgs.follows = "nixpkgs";
    character-randomizer.url = "github:jeiang/character-randomizer";
    character-randomizer.inputs.nixpkgs.follows = "nixpkgs";
    markdown-table-live-editor.url = "github:jeiang/markdown-table-live-editor";
    markdown-table-live-editor.inputs.nixpkgs.follows = "nixpkgs";
    color-hunt.url = "github:jeiang/color-hunt-validator";
    color-hunt.inputs.nixpkgs.follows = "nixpkgs";
    # Deliberately no follows: CI installs the garret client from this input's locked rev, and a different pin than garret's own cache seeding would force from-source rebuilds every run.
    garret.url = "github:jeiang/garret";
    # Deliberately no follows: upstream's uv2nix Python environment is tested against its own pin; following ours would rebuild it on every nixpkgs bump.
    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.7.30";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
