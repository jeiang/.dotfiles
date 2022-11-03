# Persistence 

{ inputs, lib, config, pkgs, ... }: {
  environment.etc = {
    # impermanence can't handle these, so have to manage here.
    "NIXOS" = {
      source = "/persist/etc/NIXOS";
    };
    "shadow" = {
      source = "/persist/etc/shadow";
    };
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      # "/var/lib/lxd"
      # "/var/lib/docker"
      "/etc/NetworkManager/system-connections"
      "/etc/nixos"
    ];
    files = [
      "/etc/machine-id"
      "/var/lib/NetworkManager/secret_key"
      "/var/lib/NetworkManager/seen-bssids"
      "/var/lib/NetworkManager/timestamps"
    ];
  };
}
