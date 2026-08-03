{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    inputs',
    self',
    ...
  }: {
    # Linux-only (Wayland shell + tools; the dms/dsearch flakes publish no
    # darwin outputs): absent on darwin rather than an eval error, so
    # output-enumerating commands work there.
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      dms = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default;
        runtimePkgs = with pkgs; [
          khal
          wtype
          cava
          cliphist
          wl-clipboard
          self'.packages.dsearch
        ];
      });
      dsearch = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs'.dsearch.packages.default;
        flags = let
          tomlFormat = pkgs.formats.toml {};
        in {
          "--config" = tomlFormat.generate "dsearch.config.toml" {
            max_depth = 12;
            exclude_dirs = [
              ".devenv"
              ".direnv"
              "result"
              ".git"
              "node_modules"
              "dist"
              "build"
              "out"
              "bin"
              "obj"
              "target"
              "vendor"
              ".gradle"
              ".m2"
              "bundle"
              ".cache"
              ".parcel-cache"
              ".next"
              ".nuxt"
              ".serverless"
              ".Trash-1000"
              "go"
              ".cargo"
              ".vscode"
            ];
          };
        };
      });
    };
  };
}
