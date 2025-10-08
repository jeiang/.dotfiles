{ pkgs, inputs, ... }:
let
  home-modules = import ./modules;
in
{
  imports = with home-modules; [
    fish
    git
    starship
    helix
    inputs.nix-index-database.homeModules.nix-index
  ];

  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    btop
    fd
    bandwhich
    bingrep
    cachix
    choose
    devenv
    duf
    erdtree
    felix-fm
    file
    hyperfine
    jq
    libtree
    ouch
    parallel
    procs
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
      icons = "auto";
      git = true;
    };
    fzf.enable = true;
    gpg = {
      enable = true;
      mutableKeys = true;
    };
    mcfly = {
      enable = true;
      fuzzySearchFactor = 2;
    };
    nix-index.enable = true;
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = true;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
      };
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
