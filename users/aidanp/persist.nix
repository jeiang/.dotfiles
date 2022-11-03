# Sets up user persistence through impermanence

{ inputs, lib, config, pkgs, ... }: {
  home.persistence."/persist/home/aidanp" = {
    directories = [
      { directory = "Desktop"; method = "symlink"; }
      { directory = "Documents"; method = "symlink"; }
      { directory = "Downloads"; method = "symlink"; }
      { directory = "Music"; method = "symlink"; }
      { directory = "Pictures"; method = "symlink"; }
      { directory = "Public"; method = "symlink"; }
      { directory = "Templates"; method = "symlink"; }
      { directory = "Videos"; method = "symlink"; }
      ".dotfiles"
      ".esp"
      ".config/discord"
      ".config/fish"
      ".config/thefuck"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/gnome-shell"
      ".local/share/keyrings"
      ".local/share/mcfly"
      ".local/share/zoxide"
      ".mozilla"
      ".renpy"
      ".ssh"
    ];
    files = [
      ".gnupg/pubring.kbx"
      ".gnupg/trustdb.gpg"
      ".config/monitors.xml"
    ];
    allowOther = true;

  };
}
