{ pkgs, ... }: {
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
}
