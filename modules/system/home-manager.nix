{inputs, ...}: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs;
    };
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
  };
}
