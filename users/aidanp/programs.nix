# Programs to install and configure through Home Manager.
{ inputs, lib, config, pkgs, ... }: {
  imports = [
    ./programs/firefox.nix
    ./programs/helix.nix
    ./programs/fish.nix
  ];
  programs = {
    alacritty.enable = true;
    aria2.enable = true;
    exa.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    bat.enable = true;
    bottom.enable = true;
    git = {
      enable = true;
      delta.enable = true;
      userName = "Aidan Pinard";
      userEmail = "aidan@aidanpinard.co";
      signing = {
        key = "C48B088F4FFBBDF0";
        signByDefault = true;
      };
      extraConfig = { init.defaultBranch = "main"; };
    };
    gpg.enable = true;
    jq.enable = true;
    just = {
      enable = true;
      enableFishIntegration = true;
    };
    mcfly = {
      enable = true;
      enableFishIntegration = true;
      fuzzySearchFactor = 2;
    };
    mpv = {
      enable = true;
      scripts = with pkgs; [ mpvScripts.mpris ];
    };
    navi = {
      enable = true;
      enableFishIntegration = true;
      settings = { cheats = { paths = [ "~/Documents/Cheats" ]; }; };
    };
    nix-index = {
      enable = true;
      enableFishIntegration = true;
    };
    obs-studio.enable = true;
    ssh = {
      enable = true;
      compression = true;
      matchBlocks = {
        "ecng3006vm" = {
          hostname = "134.209.75.252";
          user = "aidanpinard";
          identityFile = "/home/aidanp/.ssh/id_ed25519";
        };
      };
    };
    tealdeer.enable = true;
    wezterm.enable = true;
    zellij.enable = true;
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
