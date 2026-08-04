{
  inputs,
  self,
  ...
}: {
  flake = {
    darwinConfigurations.zakkart = inputs.nix-darwin.lib.darwinSystem {
      modules = [
        self.darwinModules.zakkartConfiguration
      ];
    };

    darwinModules.zakkartConfiguration = _: {
      imports = [
        self.darwinModules.base
        self.darwinModules.nix
        self.darwinModules.hjem
        self.darwinModules.sops
        self.darwinModules.homebrew
        self.darwinModules.apps
        self.darwinModules.system
        self.darwinModules.preferences
      ];

      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  };
}
