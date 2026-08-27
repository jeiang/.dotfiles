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

    # Flake output schemas: Determinate Nix's `nix flake show` reads the
    # `schemas` output to label outputs it doesn't natively know
    # (darwinConfigurations, deploy, ...); stock Nix/Lix ignores it. Lib-only
    # flake with no nixpkgs input, so there is nothing to follow.
    flake-schemas.url = "github:DeterminateSystems/flake-schemas";

    # system management inputs
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
    # Determinate manages the Nix installation on Zakkart via its
    # nix-darwin module (docs/adr/0008), whose installer owns the
    # daemon/upgrades, and on the NixOS fleet via its NixOS module
    # (docs/adr/0011). Following our nixpkgs here would be pointless anyway:
    # `determinate-nixd` is a prebuilt binary the module fetches, not
    # something this flake builds.
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
    # NetBird's own cask (the desktop app, which bundles and manages its own
    # system daemon) lives in NetBird's third-party tap, not the main
    # homebrew-cask tap -- verified via the GitHub API and its Casks/
    # listing (Casks/netbird-ui.rb).
    netbird-tap = {
      url = "github:netbirdio/homebrew-tap";
      flake = false;
    };
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";

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
    # character-randomizer: plain stdenvNoCC static build (Marvel Rivals
    # team randomizer) with no external deps beyond nixpkgs, same
    # reasoning as portfolio above.
    character-randomizer.url = "github:jeiang/character-randomizer";
    character-randomizer.inputs.nixpkgs.follows = "nixpkgs";
    # markdown-table-live-editor: plain runCommandNoCC static page (web
    # markdown table editor) with no external deps beyond nixpkgs, same
    # reasoning as portfolio above.
    markdown-table-live-editor.url = "github:jeiang/markdown-table-live-editor";
    markdown-table-live-editor.inputs.nixpkgs.follows = "nixpkgs";
    # garret: the binary cache server and client (docs/adr/0013).
    # Deliberately not following our nixpkgs -- CI installs the `garret`
    # client from this input's locked rev (.github/workflows/ci.yml), and
    # following our pin would give it a different derivation (different
    # rustc/deps) than the one garret's own CI seeds into the cache,
    # forcing a from-source rebuild on every run. Until that seeding CI
    # exists in jeiang/garret, the first CI runs build the client from
    # source regardless.
    garret.url = "github:jeiang/garret";
    # Hermes agent (upstream NixOS module consumed directly by
    # modules/nixos/hermes/). Deliberately not following our nixpkgs: the
    # upstream flake carries a uv2nix-built Python environment tested
    # against its own pin; following ours would force a full rebuild of
    # that environment on every nixpkgs bump (same reasoning as garret
    # above).
    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.7.30";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
