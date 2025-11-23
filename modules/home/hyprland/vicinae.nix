{
  config,
  pkgs,
  ...
}: {
  programs.vicinae = {
    enable = true;
    systemd.enable = true;
    settings = {
      faviconService = "twenty"; # twenty | google | none
      font.size = 11;
      popToRootOnClose = false;
      rootSearch.searchFiles = false;
      theme.name = "rose-pine";
      window = {
        csd = true;
        opacity = 0.95;
        rounding = 10;
      };
    };
    themes = {};
    extensions = with pkgs.inputs'.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      firefox
      fuzzy-files
      hypr-keybinds
      nix
      wifi-commander
      it-tools
      (config.lib.vicinae.mkRayCastExtension {
        name = "currency-exchange";
        sha256 = "sha256-E9xCXGqLKwfi1+VwMaFsbLg6yNW6aJVhzaMwIjGCwf4=";
        rev = "ed8b9fb2e0d8a0024e9a1a860a8ad827b42ed518";
      })
    ];
  };
}
