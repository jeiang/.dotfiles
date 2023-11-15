{ pkgs, ... }: {
  home.packages = with pkgs; [
    any-nix-shell
    asciinema
    bandwhich
    bingrep
    bitwarden
    borgbackup
    cachix
    choose
    cliphist
    devenv
    discord
    duf
    erdtree
    eza
    fd
    felix-fm
    file
    foliate
    gimp
    hyperfine
    jq
    libtree
    mcomix
    ouch
    parallel
    procs
    qview
    rargs
    ripgrep
    rm-improved
    rnr
    sad
    sccache
    tokei
    wl-clipboard
    wthrr
    xh
    zenith
  ];
}
