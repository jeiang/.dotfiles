{ pkgs, ... }:
let
  home-modules = import ./modules;
in
{
  imports = with home-modules; [
    fish
    git
    starship
    helix
  ];
  home.stateVersion = "24.05";

  home.packages = with pkgs;
    [
      btop
      fd
      bandwhich
      bingrep
      cachix
      choose
      devenv
      duf
      erdtree
      file
      hyperfine
      ivpn
      jq
      libtree
      ouch
      parallel
      procs
      rargs
      ripgrep
      rnr
      sad
      tokei
      xh
    ];

  programs = {
    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batdiff
        batgrep
        batman
        batman
        batwatch
      ];
    };
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    eza = {
      enable = true;
      icons = true;
      git = true;
    };
    fzf.enable = true;
    mcfly = {
      enable = true;
      fuzzySearchFactor = 2;
    };
    nix-index.enable = true;
    ssh = {
      enable = true;
      compression = true;
    };
    zoxide = {
      enable = true;
      options = [
        "--cmd"
        "cd"
      ];
    };
  };
}
