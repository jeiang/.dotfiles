{inputs, ...}: {
  nixos.modules.base.imports = [inputs.hjem.nixosModules.default];
  darwin.modules.base.imports = [inputs.hjem.darwinModules.default];

  shared.modules.base = {config, ...}: {
    hjem = {
      users.${config.preferences.user.name}.enable = true;
      clobberByDefault = true;
    };
  };
}
