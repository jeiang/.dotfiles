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
        {
          facter.reportPath = ./facter.json;
          boot = {
            loader.systemd-boot.enable = true;
            supportedFilesystems = ["ntfs"];
            tmp.cleanOnBoot = true;
          };
          networking.hostName = "artemis";
          time.timeZone = "America/Port_of_Spain";
          # set the correct ip for ipv6
          system.stateVersion = "25.05";
        }
        ./networking.nix
        ./disko-config.nix
        inputs.disko.nixosModules.disko
        inputs.nixos-facter-modules.nixosModules.facter
        inputs.home-manager.nixosModules.home-manager
        self.nixosModules.security
        self.nixosModules.nix
        self.nixosModules.sops
        self.nixosModules.home-manager
        self.nixosModules.shared
        self.nixosModules.user-root
        self.nixosModules.user-aidanp
        self.nixosModules.hyprland
        self.nixosModules.steam
        # enable wm + gui apps
        {users.aidanp.graphical = true;}
      ];
    };
  };
}
