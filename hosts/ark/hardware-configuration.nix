{ lib
, # config,
  modulesPath
, ...
}:
let
  # hostname = config.networking.hostName;
  hostname = "ark";
  unencrypted-device = "/dev/mapper/${hostname}";
  devicePath = "/dev/disk/by-partlabel";
  swapDevice = "${devicePath}/swap";
  encrypted-device = "${devicePath}/ark";
  boot-partition = "${devicePath}/boot";
  common-btrfs-opts = [ "compress=zstd" "noatime" ];
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot = {
    initrd = {
      availableKernelModules = [ "vmd" "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
      kernelModules = [ ];

      # Filesystems
      luks.devices.${hostname}.device = encrypted-device;
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = true;

  fileSystems = {
    "/" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=root" ] ++ common-btrfs-opts;
    };

    "/home" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=home" ] ++ common-btrfs-opts;
      neededForBoot = true;
    };

    "/nix" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=nix" ] ++ common-btrfs-opts;
    };

    "/persist" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=persist" ] ++ common-btrfs-opts;
      neededForBoot = true;
    };

    "/var/log" = {
      device = unencrypted-device;
      fsType = "btrfs";
      options = [ "subvol=log" ] ++ common-btrfs-opts;
      neededForBoot = true;
    };

    "/boot" = {
      device = boot-partition;
      fsType = "vfat";
    };
  };

  swapDevices = [
    { device = swapDevice; }
  ];
}
