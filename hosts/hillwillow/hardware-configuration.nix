{
  config,
  lib,
  modulesPath,
  ...
}: let
  hostname = config.networking.hostName;
  unencrypted-device = "/dev/mapper/${hostname}";
  encrypted-device = "/dev/disk/by-uuid/5f63dd70-3bb5-4c7d-b592-80ec4c011fb1";
  boot-partition = "/dev/disk/by-label/boot";
in {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot.initrd.availableKernelModules = ["xhci_pci" "nvme" "ahci" "uas" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];

  networking.useDHCP = lib.mkDefault true;
  networking.interfaces.enp2s0.useDHCP = lib.mkDefault true;
  networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;

  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Filesystems
  boot.initrd.luks.devices.${hostname}.device = encrypted-device;

  fileSystems = {
    "/" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = ["subvol=root" "compress=zstd" "noatime"];
    };

    "/home" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = ["subvol=home" "compress=zstd" "noatime"];
      neededForBoot = true;
    };

    "/nix" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = ["subvol=nix" "compress=zstd" "noatime"];
    };

    "/persist" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = ["subvol=persist" "compress=zstd" "noatime"];
      neededForBoot = true;
    };

    "/var/log" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = ["subvol=log" "compress=zstd" "noatime"];
      neededForBoot = true;
    };

    "/boot" = {
      device = boot-partition;
      fsType = "vfat";
    };
  };
}
