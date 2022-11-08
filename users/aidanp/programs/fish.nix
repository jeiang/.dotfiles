{ inputs, lib, config, pkgs, ... }: {
  programs.fish = {
    enable = true;
    shellInit = ''
      any-nix-shell fish --info-right | source
    '';
    shellAliases = {
      la = "exa -a";
      ll = "exa -l";
      lla = "exa -la";
      ls = "exa";
      lt = "exa -T";
      lta = "exa -lTa";
      cat = "bat";
      rm = "trash put"; # don't completely delete
      cd = "z"; # autojump
    };
    plugins = with pkgs; [
      {
        name = "done";
        inherit (fishPlugins.done) src;
      }
      {
        name = "tide";
        src = pkgs.fetchFromGitHub {
          owner = "IlanCosman";
          repo = "tide";
          rev = "6833806ba2eaa1a2d72a5015f59c284f06c1d2db";
          sha256 = "vi4sYoI366FkIonXDlf/eE2Pyjq7E/kOKBrQS+LtE+M=";
        };
      }
      {
        name = "bang-bang";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-bang-bang";
          rev = "f969c618301163273d0a03d002614d9a81952c1e";
          sha256 = "1r3d4wgdylnc857j08lbdscqbm9lxbm1wqzbkqz1jf8bgq2rvk03";
        };
      }
      {
        name = "thefuck";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-thefuck";
          rev = "6c9a926d045dc404a11854a645917b368f78fc4d";
          sha256 = "1n6ibqcgsq1p8lblj334ym2qpdxwiyaahyybvpz93c8c9g4f9ipl";
        };
      }
    ];
  };
}
