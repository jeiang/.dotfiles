{ config, lib, pkgs, modulesPath, ... }: {
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=root" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=persist" "compress=zstd" "noatime" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=log" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/FCC9-97AA";
    fsType = "vfat";
  };

  # Need to enable after adding lxd
  fileSystems."/persist/lxd" = {
    device = "/dev/disk/by-uuid/b396e6e1-b2dc-4b70-ace9-ac699496c981";
    fsType = "btrfs";
    options = [ "subvol=lxd" "compress=zstd" "noatime" ];
  };

  fileSystems."/persist/mnt/asahi" = {
    device = "/dev/disk/by-label/asahi";
    fsType = "ext4";
  };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/017116f9-8774-4948-a7be-e7ba3fdceeb5"; }];
}
