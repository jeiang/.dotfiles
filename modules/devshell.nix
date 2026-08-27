{inputs, ...}: {
  imports = [
    inputs.devenv.flakeModule
    inputs.treefmt-nix.flakeModule
  ];
  perSystem = {
    pkgs,
    config,
    self',
    ...
  }: {
    treefmt.config = {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
        stylua.enable = true;
      };
      flakeCheck = true;
    };
    formatter = config.treefmt.build.wrapper;
    devenv.shells = {
      default = {
        name = "system";
        packages = with pkgs;
          [
            config.treefmt.build.wrapper
            self'.packages.helix
            self'.packages.git
            deploy-rs
            disko
            dnscontrol
            fd
            fzf
            just
            nh
            nixVersions.latest
            sops
            ssh-to-age
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [
            # hyprland
            (
              inputs.wrapper-modules.lib.wrapPackage (_: {
                inherit pkgs;
                package = pkgs.lua-language-server;
                flags = {
                  "--configpath" = pkgs.writeText ".luarc.json" ''
                    {
                      "workspace": {
                        "library": [
                          "${inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland}/share/hypr/stubs"
                        ]
                      },
                      "diagnostics": {
                        "globals": ["hl"]
                      }
                    }
                  '';
                };
              })
            )
          ];
        env.NH_FLAKE = ../.;
        languages = {
          nix.enable = true;
        };
        git-hooks.hooks = {
          editorconfig-checker.enable = true;
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
