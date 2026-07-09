{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.ghostty = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = pkgs.ghostty;
      flags = {
        "--config-file" = pkgs.writeTextFile {
          name = "ghostty-config";
          text = ''
            font-family = Mononoki Nerd Font
            font-size = 13
            theme = Kanagawa Dragon
            quit-after-last-window-closed = false
            gtk-single-instance = true
          '';
        };
      };
      flagSeparator = "=";
    });
  };
}
