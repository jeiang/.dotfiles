# Theme stuff
{ inputs, outputs, lib, config, pkgs, ... }: {
  stylix = {
    image = ./wallpaper.png;
    polarity = "dark";
    base16Scheme = ./theme.yaml;
    fonts = rec {
      serif = sansSerif;
      sansSerif = {
        name = "Overpass";
        package = pkgs.overpass;
      };
      monospace = {
        name = "JetBrainsMono Nerd Font Mono";
        package = pkgs.nerdfonts.override {
          fonts = [ "JetBrainsMono" ];
        };
      };
    };
    # Disable helix because generated theme is less readable
    # than custom gruvbox
    targets.helix.enable = false;
  };
}
