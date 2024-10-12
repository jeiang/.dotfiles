_: {
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
          nixVersions.latest
          ripgrep
          just
          sops
          age
          ssh-to-age
          nixos-rebuild
          editorconfig-checker
          nh
        ];
        env.FLAKE = ./.;
        languages = {
          lua.enable = true;
          nix.enable = true;
        };
        pre-commit.hooks = {
          editorconfig-checker.enable = true;
          markdownlint = {
            enable = true;
            settings.configuration = {
              "MD013" = {
                "line_length" = 120;
              };
            };
          };
          nil.enable = true;
          statix.enable = true;
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
        };
      };
    };
  };
}
