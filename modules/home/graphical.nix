{pkgs, ...}: {
  home.packages = with pkgs; [
    discord
    bitwarden-desktop
    pwvucontrol
    jetbrains-mono
    departure-mono
    qview
    umu-launcher
    nerd-fonts.jetbrains-mono
    nerd-fonts.departure-mono
    nerd-fonts.symbols-only
    qbittorrent
    wl-clipboard
  ];

  home.sessionVariables.SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";

  fonts.fontconfig.enable = true;

  programs = {
    spotify-player = {
      enable = true;
      settings = {
        client-id = "e91bb966bf8c4f4494849daa582d857a";
        theme = "catppuccin_mocha";
      };
    };
    mpv = {
      enable = true;
      package = pkgs.mpv.override {
        youtubeSupport = true;
      };
      defaultProfiles = [
        "high-quality"
      ];
    };
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
