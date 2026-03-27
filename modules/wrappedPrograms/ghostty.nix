{
  inputs,
  self,
  ...
}: {
  flake.wrapperModules.ghostty = inputs.wrapper-modules.lib.evalModule ({
    pkgs,
    wlib,
    ...
  }: {
    imports = [
      wlib.modules.default
    ];
    config = {
      package = pkgs.ghostty;
      flags = let
        config = pkgs.writeTextFile {
          name = "ghostty-config";
          text = ''
          '';
        };
      in {
        "--config-file" = config;
      };
      flagSeparator = "=";
    };
  });

  perSystem = {pkgs, ...}: {
    packages.ghostty = self.wrapperModules.ghostty.config.wrap {
      inherit pkgs;
    };
  };
}
