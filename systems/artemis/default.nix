{
  inputs,
  self,
  ...
}: {
  flake = {
    nixosConfigurations.artemis = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ({
          pkgs,
          config,
          ...
        }: {
          facter.reportPath = ./facter.json;
          boot = {
            loader.systemd-boot.enable = true;
            supportedFilesystems = ["ntfs"];
            tmp.cleanOnBoot = true;
          };
          boot.kernelPackages = pkgs.linuxPackages_zen;
          boot.extraModulePackages = [config.boot.kernelPackages.zenpower];
          boot.kernelModules = ["zenpower"];
          # setup a symlink to /dev/dri/egpu and /dev/dri/igpu for hyprland
          services.udev.packages = let
            name = "52-gpu-symlink.rules";
            gpu-rules = pkgs.writeText name ''
              KERNEL=="card*", KERNELS=="0000:03:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/egpu"
              KERNEL=="card*", KERNELS=="0000:19:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/igpu"
            '';
            symlink-drv = pkgs.stdenv.mkDerivation {
              name = "gpu-path-rules";
              phases = ["installPhase"];

              installPhase = ''
                mkdir -p $out/lib/udev/rules.d
                cp ${gpu-rules} $out/lib/udev/rules.d/${name}
              '';
            };
          in [
            symlink-drv
          ];
          networking.hostName = "artemis";
          time.timeZone = "America/Port_of_Spain";
          # set the correct ip for ipv6
          system.stateVersion = "25.05";
        })
        {
          services.jellyfin = {
            enable = true;
            openFirewall = true;
          };
        }
        {
          # TODO: create user service to start the ui
          # TEMP: netbird config until i modify the proper instance
          services.netbird = {
            enable = true;
            clients.default.config = let
              urlConfig = {
                Scheme = "https";
                Opaque = "";
                User = null;
                Host = "netbird.jeiang.dev:443";
                Path = "";
                RawPath = "";
                OmitHost = false;
                ForceQuery = false;
                RawQuery = "";
                Fragment = "";
                RawFragment = "";
              };
            in {
              # Set Management URL for netbird configuration file
              ManagementURL = urlConfig;
              AdminUrl = urlConfig;
            };
            useRoutingFeatures = "both";
          };
        }
        ./networking.nix
        ./disko-config.nix
        inputs.disko.nixosModules.disko
        inputs.nixos-facter-modules.nixosModules.facter
        inputs.home-manager.nixosModules.home-manager
        self.nixosModules.security
        self.nixosModules.nix
        self.nixosModules.appimage
        self.nixosModules.sops
        self.nixosModules.home-manager
        self.nixosModules.shared
        self.nixosModules.user-root
        self.nixosModules.user-aidanp
        self.nixosModules.hyprland
        self.nixosModules.gaming
        self.nixosModules.ollama
        # enable wm + gui apps
        {users.aidanp.graphical = true;}
      ];
    };
  };
}
