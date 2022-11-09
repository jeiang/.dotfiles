# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)

{ inputs, outputs, lib, config, pkgs, ... }: {
  # You can import other NixOS modules here
  imports = [
    # Battery Charging Limit
    inputs.hardware.nixosModules.asus-battery

    # Hardware
    ./hardware-configuration.nix

    # Filesystems
    ./filesystems.nix

    # Impermanence
    ./impermanence.nix

    # Desktop Environment/Window Manager
    ./window-manager.nix
  ];
  # Set your system kind (needed for flakes)
  nixpkgs.hostPlatform = "x86_64-linux";

  # Define your hostname.
  networking.hostName = "asus-nixos";

  # Boot & Kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # For Keychron Keyboard
  boot.kernelModules = [ "hid-apple" ];
  # Disable Nvidia GPU for MOAR BATTERY LIFE
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
  # Note `lib.mkBefore` is used instead of `lib.mkAfter` here.
  boot.initrd.postDeviceCommands = pkgs.lib.mkBefore outputs.scripts.rollback;

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

  # Set Charging Limit
  hardware.asus.battery.chargeUpto = 60;
}
