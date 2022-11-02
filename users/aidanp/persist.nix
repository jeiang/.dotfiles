# Persistence via impermanence

{ inputs, lib, config, pkgs, ... }: {
  home.persistence."/persist/home/aidanp" = {
    directories = [
      "Desktop"
      "Documents"
      "Downloads"
      "Music"
      "Pictures"
      "Videos"
      ".dotfiles"
      ".esp"
      ".gnupg"
      ".local/share/direnv"
      ".local/share/fish/generated_completions"
      ".local/share/keyrings"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".mozilla"
      ".renpy"
      ".ssh"
    ];
    files = [ ".local/share/fish/fish_history" ];
    allowOther = true;
  };
}
