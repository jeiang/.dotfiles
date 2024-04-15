{ flake, modulesPath, lib, pkgs, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    self.nixosModules.common
    self.nixosModules.linux
    ./filesystems.nix
  ];

  # misc static system info
  system.stateVersion = "24.05";
  networking.hostName = "ark";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = true;

  # Boot & Kernel
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        consoleMode = "max";
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_xanmod_latest;
    kernel.sysctl = {
      "vm.swappiness" = 10;
    };

    # For Keychron Keyboard
    kernelModules = [ "hid-apple" "kvm-intel" ];
    kernelParams = [
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];
    # Systemd in stage 1
    initrd.systemd.enable = true;
    initrd.availableKernelModules = [ "vmd" "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
    # Use Fn Keys on Keychron Keyboard
    extraModprobeConfig = ''
      options hid_apple fnmode=2
    '';
    # Enable BTRFS and NTFS
    supportedFilesystems = [ "ntfs" "btrfs" ];
  };
  # Boot Console
  console.font = "${pkgs.terminus_font}/share/consolefonts/ter-u28n.psf.gz";

  # TPM
  security.tpm2 = {
    enable = true;
    abrmd.enable = true;
  };

  # NVME SSD
  services.fstrim.enable = true;

  # Root Config
  # users.users.root.hashedPasswordFile = config.age.secrets.ark-root-password.path;
}
