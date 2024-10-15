{ modules, users, inputs, config, modulesPath, pkgs, ... }:
let
  website-port = "8080";
in
{
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
      partitions = {
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "/rootfs" = {
                mountpoint = "/";
              };
              "/home" = {
                mountOptions = [ "compress=zstd" "noatime" ];
                mountpoint = "/home";
              };
              "/nix" = {
                mountOptions = [ "compress=zstd" "noatime" ];
                mountpoint = "/nix";
              };
            };
          };
        };
        plainSwap = {
          size = "4G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
      };
    };
  };

  # packages
  environment.systemPackages = with pkgs; [
    helix
    git
    (writeScriptBin "sudo" ''exec doas "$@"'')
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
          locations."/".proxyPass = "http://localhost:${website-port}";
        };
        "pinard.co.tt" = {
          addSSL = true;
          enableACME = true;
          locations."/".proxyPass = "http://localhost:${website-port}";
        };
        "xtra-foods.com" = {
          addSSL = true;
          enableACME = true;
          locations."/".proxyPass = "http://localhost:8081/";
        };
      };
    };
  };

  systemd.services.website = {
    enable = true;
    description = "Personal Website";
    environment = {
      SERVER_PORT = "${website-port}";
    };
    serviceConfig = {
      ExecStart = "${inputs.website.packages.x86_64-linux.default}/bin/website";
    };
  };

  security = {
    acme = {
      acceptTerms = true;
      defaults.email = "aidan@aidanpinard.co";
    };
    sudo.enable = false;
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
