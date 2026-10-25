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

    # Attached Volumes can take /dev/sda; the server disk is always LUN 0.
    boot.loader.grub = {
      enable = true;
      devices = lib.mkForce ["/dev/disk/by-path/pci-0000:06:00.0-scsi-0:0:0:0"];
    };
  };
}
