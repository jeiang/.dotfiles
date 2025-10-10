{
  inputs,
  self,
  ...
}: {
  flake = {
    nixosConfigurations.
      solder = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        {
          facter.reportPath = ./facter.json;
          boot.loader.grub.enable = true;
          boot.tmp.cleanOnBoot = true;
          networking.hostName = "solder";
          # set the correct ip for ipv6
          system.stateVersion = "25.05";
        }
        ./disko-config.nix
        ./networking.nix
        ./web-services.nix
        inputs.disko.nixosModules.disko
        inputs.nixos-facter-modules.nixosModules.facter
        inputs.home-manager.nixosModules.home-manager
        self.nixosModules.nix
        self.nixosModules.sops
        self.nixosModules.home-manager
        self.nixosModules.shared
        self.nixosModules.user-root
        self.nixosModules.user-aidanp
      ];
    };

    deploy.nodes.solder = {
      hostname = "aidanpinard.co";
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.solder;
      };
    };
  };
}
