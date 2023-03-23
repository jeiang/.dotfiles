{ config, lib, pkgs, modulesPath, ... }:
let
  encrypted-device =
    "/dev/disk/by-uuid/7bc5b4fe-9200-4bd4-b798-c2f61bca5d6e";
  unencrypted-device-name = "hillwillow";
  unencrypted-device = "/dev/mapper/${unencrypted-device-name}";
  swap-partition = { device = "/dev/disk/by-partlabel/hillwillow_swap"; };
  boot-partition = "/dev/disk/by-label/boot";
in
{
  fileSystems."/" = {
    device = unencrypted-device;
    fsType = "btrfs";
    options = [ "subvol=root" "compress=zstd" "noatime" ];
  };

  boot.initrd.luks.devices.${unencrypted-device-name}.device = encrypted-device;

  fileSystems."/home" = {
    device = unencrypted-device;
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd" "noatime" ];
  };

  fileSystems."/nix" = {
    device = unencrypted-device;
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist" = {
    device = unencrypted-device;
    fsType = "btrfs";
    options = [ "subvol=persist" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    device = unencrypted-device;
    fsType = "btrfs";
    options = [ "subvol=log" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = boot-partition;
    fsType = "vfat";
  };

  swapDevices = [
    swap-partition
  ];
}
