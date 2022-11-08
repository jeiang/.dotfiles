# Programs to install and configure through Home Manager.
{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./programs/firefox.nix
    ./programs/helix.nix
    ./programs/fish.nix
  ];
  programs = {
    alacritty = {
      enable = true;
      settings.shell.program = "zellij";
    };
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
    gpg = {
      enable = true;
      # Impermanence handles this
      mutableTrust = true;
      mutableKeys = true;
    };
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
    nushell = {
      enable = true;
      configFile.source = ./config/nushell/config.nu;
      envFile.source = ./config/nushell/env.nu;
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
    starship = {
      enable = true;
      enableFishIntegration = false;
      settings = {
        format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$python$character";
        directory = {
          style = "blue";
        };
        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
          vimcmd_symbol = "[❮](green)";
        };
        git_branch = {
          format = "[$branch]($style)";
          style = "bright-black";
        };
        git_status = {
          format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
          style = "cyan";
          conflicted = "​";
          untracked = "​";
          modified = "​";
          staged = "​";
          renamed = "​";
          deleted = "​";
          stashed = "≡";
        };
        git_state = {
          format = "\([$state( $progress_current/$progress_total)]($style)\) ";
          style = "bright-black";
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
