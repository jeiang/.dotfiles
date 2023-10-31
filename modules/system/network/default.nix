{pkgs, ...}:
# networking configuration
{
  networking = {
    wireless.enable = pkgs.lib.mkForce false;

    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      wifi.powersave = true;

      ethernet.macAddress = "random";
      wifi.macAddress = "random";
    };
    nameservers = [
      "8.8.8.8"
      "8.8.4.4"
    ];
  };

  services = {
    openssh = {
      enable = true;
      settings.UseDns = true;
    };

    # DNS resolver
    resolved.enable = true;
  };

  # Don't wait for network startup
  systemd = {
    targets.network-online.wantedBy = pkgs.lib.mkForce []; # Normally ["multi-user.target"]
    services.NetworkManager-wait-online.wantedBy = pkgs.lib.mkForce []; # Normally ["network-online.target"]
  };
}