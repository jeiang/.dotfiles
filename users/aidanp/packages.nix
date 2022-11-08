# Packages to install for current user.
{ inputs, lib, config, pkgs, ... }: {
  home.packages = with pkgs; [
    (nerdfonts.override {
      fonts = [ "FiraCode" "JetBrainsMono" "UbuntuMono" ];
    })
    any-nix-shell
    appimage-run
    axel
    bandwhich
    bingrep
    bitwarden
    borgbackup
    choose
    czkawka
    discord
    diskonaut
    duf
    eva
    fd
    file.out
    gimp
    git-crypt
    glow
    gnome3.gnome-tweaks
    hyperfine
    jql
    libtree
    lutris
    mcomix
    obsidian
    ouch
    qbittorrent
    qview
    rargs
    ripgrep
    ripgrep-all
    rm-improved # trashy & gio don't work well with impermanence
    sad
    steam-run
    szyszka
    teams
    thefuck
    tokei
    trashy
    virt-manager
    wineWowPackages.waylandFull
    wl-clipboard
    xh
    xplr
    zenith
    zoom-us
  ];
}
