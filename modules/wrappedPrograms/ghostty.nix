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
            font-family = DepartureMono Nerd Font
            font-size = 13
            theme = Kanagawa Dragon
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
