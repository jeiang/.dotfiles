{pkgs, ...}: {
  boot.plymouth = {
    enable = true;
    themePackages = [pkgs.catppuccin-plymouth];
    theme = "catppuccin-mocha";
  };
}
