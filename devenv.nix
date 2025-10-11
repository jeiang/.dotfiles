_: {
  perSystem = {
    pkgs,
    config,
    inputs',
    ...
  }: {
    treefmt.config = {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
      };
    };
    formatter = config.treefmt.build.wrapper;
    devenv.shells = {
      default = {
        name = "system";
        packages = with pkgs; [
          config.treefmt.build.wrapper
          inputs'.deploy-rs.packages.deploy-rs
          git
          helix
          nixVersions.latest
          just
          sops
          nh
        ];
        env.FLAKE = ./.;
        languages = {
          nix.enable = true;
          nix.lsp.package = pkgs.nixd;
        };
        git-hooks.hooks = {
          editorconfig-checker.enable = true;
          markdownlint = {
            enable = true;
            settings.configuration = {
              "MD013" = {
                "line_length" = 120;
              };
            };
          };
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
