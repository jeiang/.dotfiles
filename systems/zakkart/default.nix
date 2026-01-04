{
  inputs,
  self,
  ...
}: {
  flake = {
    darwinConfigurations.Zakkart = inputs.nix-darwin.lib.darwinSystem {
      specialArgs = {inherit inputs;};
      modules = [
        {
          # Required for Zakkart after Lix install
          ids.gids.nixbld = 350;
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 4;
        }
        ({pkgs, ...}: {
          users.users.aidanp = {
            name = "aidanp";
            home = "/Users/aidanp";
            shell = pkgs.fish;
          };
          programs.fish.enable = true;
          nix.settings.trusted-users = ["aidanp"];
        })
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.aidanp = {
              home.stateVersion = "25.05";
              imports = [
                self.homeModules.fish
              ];
            };
          };
        }
        inputs.home-manager.darwinModules.home-manager
        self.darwinModules.nix
      ];
    };
  };
}
