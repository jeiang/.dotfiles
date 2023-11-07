{ pkgs, ... }: {
  home.packages = [
    pkgs.openttd
    (pkgs.lutris.override {
      extraLibraries = pkgs: with pkgs; [
        gnome3.adwaita-icon-theme
        catppuccin-papirus-folders
      ];
      extraPkgs = pkgs: with pkgs; [
        mangohud
        proton-ge
        wine-tkg
      ];
    })
  ];
}
