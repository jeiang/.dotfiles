{inputs, ...}: {
  imports = [inputs.impermanence.nixosModules.home-manager.impermanence];
  home.persistence."/persist/home/aidanp" = {
    allowOther = true;
    directories = [
      "cornn-flaek"
      "Desktop"
      "Games"
      "Documents"
      "Downloads"
      "Music"
      "Pictures"
      "Programming"
      "Public"
      "Templates"
      "Videos"
      ".mozilla"
      ".renpy"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".config/discord"
      ".cache/bat"
      ".cache/nix"
      ".cache/nix-index"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [
      ".ssh/id_ed25519"
      ".ssh/id_ed25519.pub"
      ".ssh/id_rsa"
      ".ssh/id_rsa.pub"
      ".ssh/known_hosts"
      ".config/fish/fish_variables"
      ".config/cachix/config.dhall"
    ];
  };
}
