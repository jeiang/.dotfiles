# TODO: clean up this folder
{pkgs, ...}: {
  imports = [
    ./shell.nix
  ];
  home.packages = with pkgs; [
    asciinema
    bitwarden
    borgbackup
    discord
    foliate
    gimp
    mcomix
    qview
    sccache
  ];
}
