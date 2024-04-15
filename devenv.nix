_: {
  perSystem = { pkgs, config, inputs', ... }: {
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
          just
          inputs'.agenix.packages.default
          nixos-rebuild
          editorconfig-checker
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
}
