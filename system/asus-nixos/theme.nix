# Theming using stylix & base16-schemes

{ inputs, lib, config, pkgs, theme, ... }: {
  stylix = {
    image = ../../themes/${theme}/wallpaper.png;
    polarity = "dark";
    base16Scheme = "${inputs.base16-schemes}/${theme}.yaml";

    # Disable helix because generated theme is less readable
    # than custom gruvbox
    targets.helix = false;
  };
}
