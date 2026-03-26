{
  inputs,
  self,
  ...
}: {
  flake = {
    nixosConfigurations.solder = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.solderConfiguration
      ];
    };
    nixosModules.solderConfiguration = {...}: {
      imports = [
        self.nixosModules.base
        self.nixosModules.sharedConfiguration
        self.nixosModules.sops
        self.nixosModules.solderHardware
        self.nixosModules.doas

        # services
        self.nixosModules.authelia
        self.nixosModules.blocky
        self.nixosModules.caddy
        self.nixosModules.exh-home
        self.nixosModules.minecraft
        self.nixosModules.netbird
        self.nixosModules.tuwunel
        self.nixosModules.website

        # disks
        self.diskoConfigurations.solder
      ];
      netbird.management.enable = true;
      boot.loader.grub.enable = true;
      boot.tmp.cleanOnBoot = true;
      networking.hostName = "solder";
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "25.05";
      users.users.root.openssh.authorizedKeys.keys = [
        "AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
    deploy.nodes.solder = {
      hostname = "aidanpinard.co";
      sudo = "doas -u";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.solder;
      };
    };
  };
}
