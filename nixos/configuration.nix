# System Specific configuration for asus-nixos

{ inputs, outputs, lib, config, pkgs, ... }: {

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  # OpenGL
  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [ libGL ];
    setLdLibraryPath = true;
  };

  # No lecture, I am know what I am doing (hopefully)
  security.sudo.extraConfig = ''
    Defaults lecture = never
  '';

  # Virtualization
  virtualisation = {
    docker.enable = true;
    lxd = {
      enable = true;
      recommendedSysctlSettings = true;
    };
    libvirtd.enable = true;
  };

  # Programs with system-wide configuration
  programs = {
    wireshark = {
      enable = true;
      package = pkgs.wireshark-qt;
    };
    nix-ld.enable = true;
    dconf.enable = true;
    fuse.userAllowOther = true;
    # For completions
    fish.enable = true;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "22.05";
}
