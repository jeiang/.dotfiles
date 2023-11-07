{ inputs, ... }: {
  imports = [ inputs.impermanence.nixosModules.home-manager.impermanence ];
  home.persistence."/persist/home/aidanp" = {
    allowOther = true;
    directories = [
      ".cache/bat"
      ".cache/nix"
      ".cache/nix-index"
      ".config/discord"
      "cornn-flaek"
      "Desktop"
      "Documents"
      "Downloads"
      "Games"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".mozilla"
      "Music"
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
    ];
    files = [
      ".config/cachix/config.dhall"
      ".config/fish/fish_variables"
      ".local/share/nix/trusted-settings.json"
      ".ssh/id_ed25519"
      ".ssh/id_ed25519.pub"
      ".ssh/id_rsa"
      ".ssh/id_rsa.pub"
      ".ssh/known_hosts"
    ];
  };
}
