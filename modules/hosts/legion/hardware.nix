{
  nixos.modules.legion = {
    systemd.network.enable = true;
    networking = {
      useNetworkd = true;
      nftables.enable = true;
      tempAddresses = "disabled";
      firewall.enable = true;
    };
  };

  nixos.modules.hetzner = {lib, ...}: {
    hardware.facter.reportPath = ./facter.json;

    boot.loader.grub = {
      enable = true;
      devices = lib.mkForce ["/dev/sda"];
    };
  };
}
