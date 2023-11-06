{ pkgs
, config
, ...
}: {
  devenv.shells = rec {
    default = sysdev;

    sysdev = {
      name = "boul of cornn-flaek";

      packages = with pkgs; [
        config.treefmt.build.wrapper
        eza
        git
        helix
        agenix
        nix-prefetch-scripts
        nixUnstable
        nvfetcher
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

  treefmt = {
    projectRootFile = "flake.nix";
    programs = {
      deadnix.enable = true;
      nixpkgs-fmt.enable = true;
      prettier.enable = true;
      shellcheck.enable = true;
      stylua.enable = true;
      taplo.enable = true;
    };
    settings.formatter.nixpkgs-fmt.excludes = [
      "**/_sources/**"
    ];
  };
}
