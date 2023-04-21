{ pkgs, ... }: {
  home.sessionVariables = {
    # Stuff for Cargo/Rust
    CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
    RUSTC_WRAPPER = "sccache";

    # rm-improved graveyard
    GRAVEYARD = "/persist/home/aidanp/Trash";
  };

  programs = {
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batman
        batdiff
        batman
        batgrep
        batwatch
      ];
    };
    exa = {
      enable = true;
      enableAliases = true;
      icons = true;
      git = true;
    };
    fzf.enable = true;
    mcfly = {
      enable = true;
      fuzzySearchFactor = 2;
    };
    nix-index.enable = true;
    zoxide.enable = true;
  };

  home.packages = with pkgs; [
    any-nix-shell
    bandwhich
    bingrep
    choose
    cached-nix-shell
    duf
    eva
    erdtree
    fd
    felix-fm
    file
    flow
    hyperfine
    jql
    just
    libtree
    ouch
    procs
    rargs
    ripgrep
    ripgrep-all
    rm-improved
    rnr
    sad
    tokei
    wthrr
    xh
  ];
}
