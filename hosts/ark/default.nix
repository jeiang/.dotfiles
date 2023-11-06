{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];
  boot = {
    # Boot & Kernel
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    # boot.kernelPackages = pkgs.linuxKernel.kernels.linux_xanmod_latest;
    # For Keychron Keyboard
    kernelModules = ["hid-apple"];
    kernelParams = [
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];
    initrd.systemd.enable = true;
    # Use Fn Keys on Keychron Keyboard
    extraModprobeConfig = ''
      options hid_apple fnmode=2
    '';
    # Enable BTRFS and NTFS
    supportedFilesystems = ["ntfs" "btrfs"];
  };

  networking.hostName = "ark";

  # Boot Console
  console.font = "${pkgs.terminus_font}/share/consolefonts/ter-u28n.psf.gz";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Programs
  programs = {
    hyprland = {
      enable = true;
      package = inputs.hyprland.packages.x86_64-linux.hyprland;
      portalPackage = inputs.hyprportal.packages.x86_64-linux.xdg-desktop-portal-hyprland;
      xwayland.enable = true;
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      # needed for file picker
      pkgs.xdg-desktop-portal-gtk
    ];
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
