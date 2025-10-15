{
  pkgs,
  config,
  ...
}: {
  home.shell.enableFishIntegration = true;
  programs.fish = {
    enable = true;
    shellInit = ''
      ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
    '';
    shellAliases = {
      cat = pkgs.lib.mkIf config.programs.bat.enable "${pkgs.bat}/bin/bat";
    };
    shellAbbrs = {
      gcm = "git commit -m";
      gad = "git add .";
      gco = "git checkout";
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
    ];
  };
}
