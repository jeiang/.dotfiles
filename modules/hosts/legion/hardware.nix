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

      # ADR 0002 / docs/MIGRATION.md piece 0.2: Host-Native Services bind
      # directly on the nodes, so the NixOS firewall replaces reliance on
      # the Hetzner Cloud Firewall. Openings are derived in
      # modules/hosts/legion/default.nix from the service inventory.
      firewall.enable = true;
    };
  };
}
