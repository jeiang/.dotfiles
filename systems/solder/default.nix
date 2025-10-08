{ ... }:
{
  imports = [
    ./disko-config.nix
    ./networking.nix
  ];

  facter.reportPath = ./facter.json;
  boot.loader.grub.enable = true;
  boot.tmp.cleanOnBoot = true;
  networking.hostName = "solder";
  # set the correct ip for ipv6
  system.stateVersion = "25.05";
}
