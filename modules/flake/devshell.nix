{
  inputs,
  self,
  ...
}: {
  imports = [
    inputs.git-hooks-nix.flakeModule
    inputs.treefmt-nix.flakeModule
  ];
  perSystem = {
    pkgs,
    lib,
    config,
    self',
    ...
  }: {
    treefmt.config = {
      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
        stylua.enable = true;
      };
      settings.excludes = [".tack/default.nix"];
    };

    # `--inputs-from .` cannot see tack pins, so these are flake outputs.
    packages = {
      inherit (pkgs) dnscontrol hcloud jq rsync;
      nb-nix = inputs.nb-nix.packages.${pkgs.stdenv.hostPlatform.system}.nb-nix;
      tack = inputs.tack.packages.${pkgs.stdenv.hostPlatform.system}.tack;
    };

    pre-commit = {
      # statix and treefmt already run as their own flake checks.
      check.enable = false;
      settings = {
        package = pkgs.prek;
        hooks = {
          editorconfig-checker = {
            enable = true;
            # sops owns the shards' bytes.
            excludes = [self.lib.sopsShardRegex];
          };
          statix = {
            enable = true;
            # Explicit file names skip statix.toml's ignore, and .tack is generated.
            excludes = [".tack/"];
          };
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
        };
      };
    };

    devShells.default = pkgs.mkShell {
      name = "system";
      # age-plugin-yubikey panics on a NotWellFormed locale when LANG/LC_ALL
      # are empty or "C" (e.g. a fresh macOS shell), which breaks sops.
      LANG = "en_US.UTF-8";
      shellHook = config.pre-commit.installationScript;
      packages = with pkgs;
        [
          config.treefmt.build.wrapper
          self'.packages.helix
          self'.packages.git
          self'.packages.tack
          inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
          age-plugin-se
          age-plugin-yubikey
          disko
          dnscontrol
          fd
          fzf
          hcloud
          jq
          just
          nh
          nixd
          nix-fast-build
          sops
          ssh-to-age
          statix
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
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
    };
  };
}
