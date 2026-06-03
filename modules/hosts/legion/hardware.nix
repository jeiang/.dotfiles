{
  flake.nixosModules.legionHardware = {lib, ...}: {
    hardware.facter.reportPath = ./facter.json;

    boot.loader.grub.devices = lib.mkForce ["/dev/sda"];
    systemd.network = {
      enable = true;
      networks."10-wan" = {
        matchConfig.Name = "enp1s0";
        routes = [
          {
            Gateway = "fe80::1";
          }
        ];
      };
    };
    networking = {
      useNetworkd = true;
      nftables.enable = true;
      tempAddresses = "disabled";

      # configure firewall
      firewall = {
        enable = true;
        allowedTCPPorts = [
          22
        ];
      };
    };
  };
}
