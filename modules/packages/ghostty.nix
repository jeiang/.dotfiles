{
  self,
  inputs,
  ...
}: {
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
          # Colors come from flake.lib.palette (modules/theme.nix) so the
          # terminal matches helix's kanabox-dark-hard theme; the ANSI 16
          # mapping follows kanagawa.nvim's "wave" terminal colors.
          text = let
            p = self.lib.palette.kanaboxDarkHard;
            ansi = with p; [
              sumiInk0
              autumnRed
              autumnGreen
              boatYellow2
              crystalBlue
              oniViolet
              waveAqua1
              oldWhite
              fujiGray
              waveRed
              springGreen
              carpYellow
              springBlue
              springViolet1
              waveAqua2
              fujiWhite
            ];
            palette = builtins.concatStringsSep "\n" (inputs.nixpkgs.lib.imap0 (i: c: "palette = ${toString i}=${c}") ansi);
          in ''
            font-family = Mononoki Nerd Font
            font-size = 13
            background = ${p.sumiInk1}
            foreground = ${p.fujiWhite}
            cursor-color = ${p.springViolet2}
            cursor-text = ${p.sumiInk1}
            selection-background = ${p.waveBlue1_5}
            selection-foreground = ${p.fujiWhite}
            ${palette}
            quit-after-last-window-closed = false
            gtk-single-instance = true
          '';
        };
      };
      flagSeparator = "=";
    });
  };
}
