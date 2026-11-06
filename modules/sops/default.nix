{inputs, ...}: {
  nixos.modules.base = {
    imports = [inputs.sops-nix.nixosModules.sops];
    sops.useSystemdActivation = true;
  };

  darwin.modules.base.imports = [inputs.sops-nix.darwinModules.sops];
}
