{ pkgs
, inputs
, ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];
  boot = {
    # Boot & Kernel
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
    kernelModules = [ "hid-apple" ];
    kernelParams = [
      "quiet"
      "loglevel=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];
    # Systemd in stage 1
    initrd.systemd.enable = true;
    # Use Fn Keys on Keychron Keyboard
    extraModprobeConfig = ''
      options hid_apple fnmode=2
    '';
    # Enable BTRFS and NTFS
    supportedFilesystems = [ "ntfs" "btrfs" ];
  };

  networking.hostName = "ark";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 111 2049 4000 4001 4002 20048 ];
    allowedTCPPortRanges = [
      {
        from = 8000;
        to = 8100;
      }
    ];
    allowedUDPPorts = [ 111 2049 4000 4001 4002 20048 ];
  };

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

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
    daemon.settings = {
      data-root = "/persist/docker";
    };
  };
  users.extraGroups.docker.members = [ "aidanp" ];

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

  system.stateVersion = "23.11";
}
