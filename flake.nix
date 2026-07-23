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
    # jkmn-website: plain stdenvNoCC static build with no external deps
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

    # Hermes' NixOS module is upstream best-effort, so pin releases and
    # update this input only through a focused, validated maintenance change.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.7.7";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
}
