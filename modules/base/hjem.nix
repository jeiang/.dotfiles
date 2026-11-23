{
  self,
  inputs,
  ...
}: {
  nixos.modules.base.imports = [inputs.hjem.nixosModules.default];
  darwin.modules.base.imports = [inputs.hjem.darwinModules.default];

  shared.modules.base = _: {
    hjem = {
      users.${self.lib.facts.userName}.enable = true;
      clobberByDefault = true;
    };
  };
}
