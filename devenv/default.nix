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
        eza
        ripgrep
        helix
        git
        nixUnstable
        config.treefmt.build.wrapper
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
      alejandra.enable = true;
      deadnix.enable = true;
      prettier.enable = true;
      shellcheck.enable = true;
      stylua.enable = true;
      taplo.enable = true;
    };
  };
}
