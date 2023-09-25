{pkgs, ...}: {
  home.packages = with pkgs; [
    amberol
    asciinema
    bitwarden
    borgbackup
    discord
    foliate
    gimp
    lutris
    mcomix
    qview
    sccache
  ];
}
