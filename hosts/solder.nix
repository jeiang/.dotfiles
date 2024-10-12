{ modules, users, inputs, config, modulesPath, pkgs, ... }: {
  imports = [
    modules.sops
    modules.nix
    modules.home-manager
    users.aidanp
    inputs.disko.nixosModules.disko
    (modulesPath + "/profiles/qemu-guest.nix") # hardware-configuration.nix
  ];

  users.users.root.hashedPasswordFile = config.sops.secrets."passwords/solder-root".path;

  boot = {
    kernelParams = [ "console=ttyS0,19200n8" ];
    initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "ahci" "sd_mod" ];
    # Use the GRUB 2 boot loader.
    loader.grub = {
      enable = true;
      extraConfig = ''
        serial --speed=19200 --unit=0 --words=8 --parity=no --stop=1;
        terminal_input serial;
        terminal_output serial
      '';
      forceInstall = true; # something something linode
      device = "nodev";
    };
    loader.timeout = 10; # account for LISH delays
  };

  # Networking configuration
  networking = {
    usePredictableInterfaceNames = false;
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
    firewall = {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 80 443 ];
    };
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions.root = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
        };
      };
    };
  };

  # packages
  environment.systemPackages = with pkgs; [
    helix
    git
    # (writeScriptBin "sudo" ''exec doas "$@"'')
  ];
  programs = {
    fish.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
    };
    longview = {
      enable = true;
      apiKeyFile = config.sops.secrets."linode/longview-token".path;
      nginxStatusUrl = "http://localhost/nginx_status";
    };
    nginx = {
      enable = true;
      statusPage = true;
      virtualHosts = {
        "aidanpinard.co" = {
          addSSL = true;
          enableACME = true;
          locations."/".proxyPass = "http://localhost:8080";
        };
        "pinard.co.tt" = {
          addSSL = true;
          enableACME = true;
          locations."/".proxyPass = "http://localhost:8080";
        };
        "xtra-foods.com" = {
          addSSL = true;
          enableACME = true;
          locations."/".proxyPass = "http://localhost:8081/";
        };
      };
    };
  };

  security = {
    acme = {
      acceptTerms = true;
      defaults.email = "aidan@aidanpinard.co";
    };
    sudo.enable = true;
    doas = {
      enable = true;
      wheelNeedsPassword = false;
      extraRules = [{
        users = [ "aidanp" ];
        keepEnv = true;
        persist = true;
      }];
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.11";
}
