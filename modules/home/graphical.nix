{pkgs, ...}: {
  home.packages = with pkgs; [
    discord
  ];

  programs = {
    firefox = {
      enable = true;
      profiles.main = {
        id = 0;
        containersForce = true;
        containers = {
          gaming = {
            id = 0;
            color = "blue";
            icon = "chill";
          };
          youtube = {
            id = 1;
            color = "red";
            icon = "fence";
          };
        };
        extensions = {
          # TODO: add tabs2txt cookies.txt & openmultipleurl
          packages = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            bitwarden
            stylus
          ];
          force = true;
          settings = {
            # Bitwarden
            "{446900e4-71c2-419f-a6a7-df9c091e268b}".settings = {
            };
            "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}".settings = {
              dbInChromeStorage = true; # required for Stylus
            };
            "uBlock0@raymondhill.net".settings = {
              selectedFilterLists = [
                "ublock-filters"
                "ublock-badware"
                "ublock-privacy"
                "ublock-unbreak"
                "ublock-quick-fixes"
              ];
            };
          };
        };
        settings = {
          "extensions.autoDisableScopes" = 0;
        };
      };
    };
  };
}
