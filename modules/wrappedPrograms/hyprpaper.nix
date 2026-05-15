{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.hyprpaper = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = pkgs.hyprpaper;
      flags = {
        "--config" = pkgs.writeText "hyprpaper.conf" ''
          wallpaper {
              monitor =
              path = ${self}/assets/wallpaper.jpg
              fit_mode = cover
          }
        '';
      };
    });
  };
}
