{ profiles, pkgs, ... }: {
  imports = [
    # profiles.networking
    profiles.nixos
    profiles.users.root # make sure to configure ssh keys
    profiles.users.nixos
  ];

  # HACK: just to satify stylix, despite it not being used.
  stylix.image = pkgs.fetchurl {
    url = "https://www.pixelstalk.net/wp-content/uploads/2016/05/Epic-Anime-Awesome-Wallpapers.jpg";
    sha256 = "enQo3wqhgf0FEPHj2coOCvo7DuZv+x5rL/WIo4qPI50=";
  };

  boot.loader.systemd-boot.enable = true;

  # Required, but will be overridden in the resulting installer ISO.
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; };

  system.stateVersion = "23.05";
}
