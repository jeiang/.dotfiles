# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{ inputs, lib, config, pkgs, ... }: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Filesystems were removed from hardware scan. Included here for custom setup
    ./filesystems.nix
    # Modified asus battery modules from nixos-hardware. Battery is BAT1 not BAT0 on ASUS TUF FA506IV
    ./hardware/battery.nix
    # Persistence
    ./persist.nix
    # Theme
    ./theme.nix
  ];

  # Config for flakes from https://github.com/Misterio77/nix-starter-configs
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}")
      config.nix.registry;
  };

  # Enable flakes, dedup & gc weekly
  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Set system kind (needed for flakes)
  nixpkgs.hostPlatform = "x86_64-linux";

  # Boot & Kernel
  # For Keychron Keyboard
  boot.kernelModules = [ "hid-apple" ];
  # Disable Nvidia GPU for MOAR BATTERY LIFE
  boot.kernelParams = [ "module_blacklist=nouveau" ];
  # Use Fn Keys on Keychron Keyboard
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2
  '';
  # Enable BTRFS and NTFS
  boot.supportedFilesystems = [ "ntfs" "btrfs" ];
  # systemd-boot because grub is big dumb dumb sometimes
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;

  # Note `lib.mkBefore` is used instead of `lib.mkAfter` here.
  boot.initrd.postDeviceCommands = pkgs.lib.mkBefore ''
    mkdir -p /mnt

    # We first mount the btrfs root to /mnt
    # so we can manipulate btrfs subvolumes.
    mount -o subvol=/ /dev/mapper/enc /mnt

    # While we're tempted to just delete /root and create
    # a new snapshot from /@root, /root is already
    # populated at this point with a number of subvolumes,
    # which makes `btrfs subvolume delete` fail.
    # So, we remove them first.
    #
    # /root contains subvolumes:
    # - /root/var/lib/portables
    # - /root/var/lib/machines
    #
    # I suspect these are related to systemd-nspawn, but
    # since I don't use it I'm not 100% sure.
    # Anyhow, deleting these subvolumes hasn't resulted
    # in any issues so far, except for fairly
    # benign-looking errors from systemd-tmpfiles.
    btrfs subvolume list -o /mnt/root |
    cut -f9 -d' ' |
    while read subvolume; do
      echo "deleting /$subvolume subvolume..."
      btrfs subvolume delete "/mnt/$subvolume"
    done &&
    echo "deleting /root subvolume..." &&
    btrfs subvolume delete /mnt/root

    echo "restoring blank /root subvolume..."
    btrfs subvolume snapshot /mnt/@root /mnt/root

    # Assuming no subvolumes inside user home
    echo "deleting /home/aidanp subvolume..." &&
    btrfs subvolume delete /mnt/home/aidanp

    echo "restoring blank /home/aidanp subvolume..." &&
    btrfs subvolume snapshot /mnt/home/@aidanp /mnt/home/aidanp

    # Because the image is restored by root, we don't have permissions
    # for the home folder, which makes home manager act weird. So make
    # aidanp own the folder like they should. aidanp uid = 1000.
    chown 1000 /mnt/home/aidanp

    # Once we're done rolling back to a blank snapshot,
    # we can unmount /mnt and continue on the boot process.
    umount /mnt
  '';

  # Define your hostname.
  networking.hostName = "asus-nixos";

  # Networking
  networking.networkmanager.enable =
    true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/Port_of_Spain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

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
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define primary user account
  users.users.aidanp = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "lxd"
      "wireshark"
      "dialout"
      "libvirtd"
    ];
    packages = with pkgs; [ fortune cowsay ];
  };

  # Install system wide packages
  environment.systemPackages = with pkgs; [
    # Vim instead of Nano
    vim
    wget
  ];

  # Programs with system-wide configuration
  programs = {
    wireshark = {
      enable = true;
      package = pkgs.wireshark-qt;
    };
    nix-ld.enable = true;
    dconf.enable = true;
    fuse.userAllowOther = true;
  };

  # Disable sudo lecture every boot because of rollback to blank
  security.sudo.extraConfig = ''
    Defaults lecture = never
  '';

  # Virtualization
  #  virtualisation = {
  #    docker.enable = true;
  #    lxd = {
  #      enable = true;
  #      recommendedSysctlSettings = true;
  #    };
  #    # TODO ENABLE and setup persistence
  #    # libvirtd.enable = true;
  #  };

  # Set Charging Limit
  hardware.asus.battery.chargeUpto = 60;

  # OpenGL
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [ libGL ];
    setLdLibraryPath = true;
  };

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}
