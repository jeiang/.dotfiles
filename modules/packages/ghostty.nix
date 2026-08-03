{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.ghostty = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      # pkgs.ghostty is Linux-only; pkgs.ghostty-bin is nixpkgs' prebuilt
      # macOS .app (with its own $out/bin/ghostty wrapper), used on darwin
      # instead. This branch is eval-time only and never touches the Linux
      # value above it.
      package =
        if pkgs.stdenv.hostPlatform.isDarwin
        then pkgs.ghostty-bin
        else pkgs.ghostty;
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
