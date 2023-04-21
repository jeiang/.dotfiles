{
  security.sudo.extraConfig = "Defaults lecture=\"never\"";

  environment.etc = {
    # Not 100% sure if I need this, but should test
    "NIXOS".text = "";
    machine-id.source = ./machine-id;
    adjtime.source = ./adjtime;
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/NetworkManager/system-connections"
      "/var/lib/bluetooth"
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/var/lib/NetworkManager/secret_key"
      "/var/lib/NetworkManager/seen-bssids"
      "/var/lib/NetworkManager/timestamps"
    ];
    users.aidanp = {
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
        ".cargo"
        ".config/discord"
        ".config/fish"
        ".config/qBittorrent"
        ".config/thefuck"
        ".config/weathercrab"
        ".cache/bat"
        ".cache/cached-nix-shell"
        ".cache/nix"
        ".cache/nix-index"
        ".cache/sccache"
        ".local/share/direnv"
        ".local/share/fish"
        ".local/share/mcfly"
        ".local/share/qBittorrent"
        ".local/share/zoxide"
        ".mozilla"
        ".renpy"
        { directory = ".ssh"; mode = "0700"; }
        { directory = ".local/share/keyrings"; mode = "0700"; }
      ];
      files = [
        ".cache/tofi-drun"
      ];
    };
  };
}
