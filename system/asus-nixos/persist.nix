# Persistence 

{ inputs, lib, config, pkgs, ... }: {
  # # Setting up /etc & /var bindings for persistence
  # environment.etc = {
  #   nixos.source = "/persist/etc/nixos";
  #   "NetworkManager/system-connections".source =
  #     "/persist/etc/NetworkManager/system-connections";
  #   adjtime.source = "/persist/etc/adjtime";
  #   NIXOS.source = "/persist/etc/NIXOS";
  #   machine-id.source = "/persist/etc/machine-id";
  #   shadow.source = "/persist/etc/shadow";
  # };
  # systemd.tmpfiles.rules = [
  #   "L /var/lib/NetworkManager/secret_key - - - - /persist/var/lib/NetworkManager/secret_key"
  #   "L /var/lib/NetworkManager/seen-bssids - - - - /persist/var/lib/NetworkManager/seen-bssids"
  #   "L /var/lib/NetworkManager/timestamps - - - - /persist/var/lib/NetworkManager/timestamps"
  #   "L /var/lib/lxd - - - - /persist/var/lib/lxd"
  #   "L /var/lib/docker - - - - /persist/var/lib/docker"
  # ];

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/lxd"
      "/var/lib/docker"
      "/etc/NetworkManager/system-connections"
      "/etc/nixos"
    ];
    files = [
      "etc/nixos"
      "etc/adjtime"
      "etc/NIXOS"
      "etc/machine-id"
      "etc/shadow"
      "var/lib/NetworkManager/secret_key"
      "var/lib/NetworkManager/seen-bssids"
      "var/lib/NetworkManager/timestamps"
    ];
  };
}
