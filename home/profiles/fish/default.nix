{ pkgs, lib, config, ... }: {
  home.packages = with pkgs; [ thefuck ];
  programs.fish = {
    enable = true;
    shellInit = ''
      ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
    '';
    shellAliases = {
      cat = lib.mkIf config.programs.bat.enable "${pkgs.bat}/bin/bat";
      # Only use cd -> z if zoxide has generated the binding
      cd = lib.mkIf (config.programs.zoxide.enable && config.programs.zoxide.enableFishIntegration) "z"; # autojump
    };
    shellAbbrs = {
      # home manager doesn't support setting cursor position
      gcm = "git commit -m";
      gad = "git add .";
      gco = "git checkout";
      snsf = "sudo nixos-rebuild switch --flake";
      snbf = "sudo nixos-rebuild boot --flake";
    };
    plugins = with pkgs; [
      {
        name = "done";
        inherit (fishPlugins.done) src;
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
