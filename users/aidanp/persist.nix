# Sets up user persistence through impermanence

{inputs, lib, config, pkgs, ...}: {
  home.persistence."/persist/home/aidanp" = {
    directories = [
      "Desktop"
      "Documents"
      "Downloads"
      "Music"
      "Pictures"
      "Public"
      "Templates"
      "Videos"
      ".dotfiles"
      ".esp"
      ".gnupg"
      ".config/discord"
      ".local/share/direnv"
      ".local/share/fish/generated_completions"
      ".local/share/keyrings"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".mozilla"
      ".renpy"
      ".ssh"
    ];
    files = [ 
      ".local/share/fish/fish_history"
      ".config/fish/fish_variables"
    ];
    allowOther = true;
  };
}
