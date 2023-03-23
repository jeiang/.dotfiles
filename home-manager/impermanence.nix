{ inputs, outputs, lib, config, pkgs, ... }: {
  home.persistence."/persist/home/aidanp" = {
    directories = [
      { directory = "Desktop"; method = "symlink"; }
      { directory = "Games"; method = "symlink"; }
      { directory = "Documents"; method = "symlink"; }
      { directory = "Downloads"; method = "symlink"; }
      { directory = "Music"; method = "symlink"; }
      { directory = "Pictures"; method = "symlink"; }
      { directory = "Public"; method = "symlink"; }
      { directory = "Templates"; method = "symlink"; }
      { directory = "Videos"; method = "symlink"; }
      ".dotfiles"
      ".esp"
      ".cargo"
      ".config/discord"
      ".config/fish"
      ".config/qBittorrent"
      ".config/thefuck"
      ".cache/nix-index"
      ".local/share/direnv"
      ".local/share/fish"
      ".local/share/gnome-shell"
      ".local/share/keyrings"
      ".local/share/mcfly"
      ".local/share/qBittorrent"
      ".local/share/zoxide"
      ".mozilla"
      ".renpy"
      ".ssh"
    ];
    files = [
      ".config/monitors.xml"
      ".config/mimeapps.list"
    ];
    allowOther = true;
  };
}
