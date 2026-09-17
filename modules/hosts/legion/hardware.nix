{
  nixos.modules.legion = {lib, ...}: {
    hardware.facter.reportPath = ./facter.json;

    boot.loader.grub.devices = lib.mkForce ["/dev/sda"];
    systemd.network.enable = true;
    networking = {
      useNetworkd = true;
      nftables.enable = true;
      tempAddresses = "disabled";
      firewall.enable = true;
    };
  };
}
