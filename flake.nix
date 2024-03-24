{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [
        inputs.nixos-flake.flakeModule
        inputs.treefmt-nix.flakeModule
        inputs.devenv.flakeModule
        ./users
      ];

      perSystem = { pkgs, config, ... }: {
        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            nixpkgs-fmt.enable = true;
            deadnix.enable = true;
            prettier.enable = true;
            shellcheck.enable = true;
            stylua.enable = true;
            taplo.enable = true;
          };
        };
        formatter = config.treefmt.build.wrapper;
        devenv.shells = {
          default = {
            name = "sysconf-dev";
            packages = with pkgs; [
              config.treefmt.build.wrapper
              eza
              git
              helix
              nixUnstable
              ripgrep
            ];
            languages = {
              lua.enable = true;
              nix.enable = true;
            };
            pre-commit = {
              hooks = {
                editorconfig-checker.enable = true;
                markdownlint.enable = true;
                nil.enable = true;
                statix.enable = true;
                treefmt.enable = true;
              };
              settings = {
                treefmt.package = config.treefmt.build.wrapper;
                markdownlint.config = {
                  "MD013" = {
                    "line_length" = 120;
                  };
                };
              };
            };
          };
        };
      };
      flake = { };
    };

  inputs = {
    # Principle inputs (updated by `nix run .#update`)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:lnl7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Utility inputs
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-flake.url = "github:srid/nixos-flake";

    # Devshell
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };
}
