{ inputs, ... }: {
  imports = [ inputs.impermanence.nixosModules.home-manager.impermanence ];
  home.persistence."/persist/home/aidanp" = {
    allowOther = true;
    directories = [
      ".cache/bat"
      ".cache/lutris"
      ".cache/nix"
      ".cache/nix-index"
      ".cache/swww"
      ".config/discord"
      ".config/fish"
      ".config/lutris"
      ".config/modorganizer2"
      ".config/qBittorrent"
      "cornn-flaek"
      "Desktop"
      "Documents"
      "Downloads"
      "Games"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".local/share/qBittorrent"
      ".mozilla"
      "Music"
      ".parallel"
      "Pictures"
      "Programming"
      "Public"
      ".renpy"
      "Templates"
      "Videos"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
      {
        directory = ".local/share/lutris";
        method = "symlink";
      }
    ];
    files = [
      ".config/cachix/config.dhall"
      ".local/share/nix/trusted-settings.json"
      ".ssh/id_ed25519"
      ".ssh/id_ed25519.pub"
      ".ssh/id_rsa"
      ".ssh/id_rsa.pub"
      ".ssh/known_hosts"
    ];
  };
}
