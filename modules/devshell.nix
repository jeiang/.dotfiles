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
        # age-plugin-yubikey panics on a NotWellFormed locale when LANG/LC_ALL
        # are empty or "C" (e.g. a fresh macOS shell), which breaks sops.
        env.LANG = "en_US.UTF-8";
        packages = with pkgs;
          [
            config.treefmt.build.wrapper
            self'.packages.helix
            self'.packages.git
            inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
            age-plugin-yubikey
            disko
            dnscontrol
            fd
            fzf
            just
            nh
            nix-fast-build
            sops
            ssh-to-age
            watchexec
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
