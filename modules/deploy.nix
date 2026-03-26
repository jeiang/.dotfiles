{
  inputs,
  self,
  ...
}: {
  flake = {
    checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
  };
}
