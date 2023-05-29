{ pkgs, ... }: {
  home.packages = with pkgs; [
    amberol
    appimage-run
    asciinema
    bitwarden
    borgbackup
    czkawka
    discord
    foliate
    gimp
    git-crypt
    lutris
    mcomix
    obsidian
    pandoc
    qbittorrent
    qview
    sccache
    szyszka
    texlive.combined.scheme-small
    zoom-us
  ];
}
