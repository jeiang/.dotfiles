{
  inputs,
  pkgs,
  ...
}: {
  imports = [./hardware-configuration.nix];

  # hostname
  networking.hostName = "hillwillow";

  # Boot & Kernel
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxKernel.kernels.linux_xanmod_latest;
  # For Keychron Keyboard
  boot.kernelModules = ["hid-apple"];
  boot.kernelParams = [
    # Disable Nvidia GPU
    # "module_blacklist=nouveau"
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
    "amd_pstate=active"
  ];
  # Use Fn Keys on Keychron Keyboard
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2
  '';
  # Enable BTRFS and NTFS
  boot.supportedFilesystems = ["ntfs" "btrfs"];

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Set Charging Limit
  hardware.asus.battery.chargeUpto = 60;

  # Programs
  programs = {
    hyprland = {
      enable = true;
      package = inputs.hyprland.packages.x86_64-linux.hyprland;
      xwayland.enable = true;
      nvidiaPatches = true;
    };

    # TODO: handle custom steam versions
    steam.enable = true;
  };

  # TPM
  security.tpm2 = {
    enable = true;
    abrmd.enable = true;
  };

  # NVME SSD
  services.fstrim.enable = true;

  system.stateVersion = "23.05";
}
