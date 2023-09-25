{
  pkgs,
  config,
  ...
}: {
  devenv.shells = rec {
    default = sysdev;

    sysdev = {
      name = "boul of cornn-flaek";

      packages = with pkgs; [
        helix
        git
        nixUnstable
        config.treefmt.build.wrapper
      ];

      languages.lua.enable = true;
      languages.nix.enable = true;

      pre-commit.hooks = {
        editorconfig-checker.enable = true;
        markdownlint.enable = true;
        nil.enable = true;
        statix.enable = true;
        treefmt.enable = true;
      };

      pre-commit.settings.treefmt.package = config.treefmt.build.wrapper;

      pre-commit.settings.markdownlint.config = {
        "MD013" = {
          "line_length" = 120;
        };
      };
    };
  };

  treefmt = {
    projectRootFile = "flake.nix";
    programs = {
      alejandra.enable = true;
      deadnix.enable = true;
      prettier.enable = true;
      shellcheck.enable = true;
      stylua.enable = true;
      taplo.enable = true;
    };
  };
}
