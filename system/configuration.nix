# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball
      {
        url = "https://github.com/nix-community/NUR/archive/117eeb43bca6f66f68d2ec2365b5950683096bc4.tar.gz";
        sha256 = "0w9z6x7yiiyvp13fb1z3v5xwkqk8jlla1zbdnzq2djb6z1h4aw8c";
      }
    ) {
      inherit pkgs;
    };
  };

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./hardware/battery.nix
    ];

  # Kernel Stuff
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "hid-apple" ];
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2 
  '';

  # Set Charging Limit
  hardware.asus.battery.chargeUpto = 60;

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      libGL
    ];
    setLdLibraryPath = true;
  };

  # Bootloader.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.grub = {
    enable = true;
    useOSProber = true;
    device = "nodev";
    efiSupport = true;
  };

  # Filesystems
  fileSystems."/mnt/asahi" ={ 
    device = "/dev/disk/by-label/asahi";
    fsType = "ext4";
  };

  # Define your hostname.
  networking.hostName = "asus-nixos";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Port_of_Spain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.utf8";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define primary user account.
  users.users.aidanp = {
    isNormalUser = true;
    description = "Aidan Pinard";
    extraGroups = [ "networkmanager" "wheel" "docker" "wireshark" "dialout" "libvirtd" ];
    packages = with pkgs; [ fortune ];
  };
  
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Packages installed in system profile.
  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  # System-wide Packages with configuration
  programs = {
    wireshark.enable = true;
    wireshark.package = pkgs.wireshark-qt;
    nix-ld.enable = true;
    dconf.enable = true;
  };

  # Enable and other virtualization
  virtualisation.docker.enable = true;
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "aidanp" ];
  virtualisation.libvirtd.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}
