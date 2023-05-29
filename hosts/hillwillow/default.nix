{ suites, pkgs, ... }:
{
  imports = suites.laptop ++ [
    ./hardware-configuration.nix
    ./impermanence.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Boot & Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # For Keychron Keyboard
  boot.kernelModules = [ "hid-apple" ];
  # Disable Nvidia GPU
  boot.kernelParams = [
    "module_blacklist=nouveau"
    "quiet"
    "loglevel=3"
    "systemd.show_status=auto"
    "rd.udev.log_level=3"
  ];
  # Use Fn Keys on Keychron Keyboard
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2
  '';
  # Enable BTRFS and NTFS
  boot.supportedFilesystems = [ "ntfs" "btrfs" ];
  # In case of crash (happened at least twice)
  boot.crashDump.enable = true;

  # Networking
  networking.networkmanager.enable = true;
  networking.nameservers = [
    "8.8.8.8"
    "8.8.4.4"
  ];

  # Set your time zone.
  time.timeZone = "America/Port_of_Spain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Power Management
  powerManagement.powertop.enable = true;
  services.power-profiles-daemon.enable = true;

  # Set Charging Limit
  hardware.asus.battery.chargeUpto = 60;

  system.stateVersion = "23.05";
}
