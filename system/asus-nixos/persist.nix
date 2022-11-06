# Persistence 

{ inputs, lib, config, pkgs, ... }: {
  environment.etc = {
    # This file is always empty for some reason, just set to to nothing here.
    "NIXOS".text = "";
    # impermanence can't handle this, so have to manage it here.
    "shadow" = {
      source = "/persist/etc/shadow";
    };
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/lxd"
      "/var/lib/docker"
      "/var/lib/libvirt"
      "/etc/NetworkManager/system-connections"
      "/etc/nixos"
      "/var/lib/bluetooth"
      {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
        mode = "u=rwx,g=rx,o=";
      }
    ];
    files = [
      "/etc/machine-id"
      "/var/lib/NetworkManager/secret_key"
      "/var/lib/NetworkManager/seen-bssids"
      "/var/lib/NetworkManager/timestamps"
    ];
  };
}
