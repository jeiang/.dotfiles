{inputs, ...}: {
  imports = [
    inputs.devenv.flakeModule
    inputs.treefmt-nix.flakeModule
  ];
  perSystem = {
    pkgs,
    config,
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
          deploy-rs
          fd
          fzf
          git
          helix
          just
          nh
          nixVersions.latest
          sops
          ssh-to-age
        ];
        # used for NH
        env.NH_FLAKE = ./.;
        languages = {
          nix.enable = true;
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
