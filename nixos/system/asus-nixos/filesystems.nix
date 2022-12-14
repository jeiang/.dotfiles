{ config, lib, pkgs, modulesPath, ... }: {
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
    fsType = "btrfs";
    options = [ "subvol=root" "compress=zstd" "noatime" ];
  };

  boot.initrd.luks.devices."enc".device = "/dev/disk/by-uuid/7bc5b4fe-9200-4bd4-b798-c2f61bca5d6e";

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist" = {
    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
    fsType = "btrfs";
    options = [ "subvol=persist" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
    fsType = "btrfs";
    options = [ "subvol=log" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  #  fileSystems."/persist/lxd" = {
  #    device = "/dev/disk/by-uuid/b060d466-a3f1-4b78-8ffa-745824bb4122";
  #    fsType = "btrfs";
  #    options = [ "subvol=lxd" "compress=zstd" "noatime" ];
  #  };

  #  fileSystems."/persist/mnt/asahi" = {
  #    device = "/dev/disk/by-label/asahi";
  #    fsType = "btrfs";
  #    options = [ "subvol=root" "compress=zstd" "noatime" ];
  #  };

  swapDevices =
    [{ device = "/dev/disk/by-partlabel/hillwillow_swap"; }];
}
