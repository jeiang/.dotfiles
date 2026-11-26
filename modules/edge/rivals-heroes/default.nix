{
  self,
  inputs,
  ...
}: {
  nixos.modules.edge = {pkgs, ...}: {
    edge.sites.${self.lib.toolSites.rivals.hostname} = {
      content = true;
      appsec = false;
      config = ''
        handle {
          appsec
          root * ${inputs.character-randomizer.packages.${pkgs.stdenv.hostPlatform.system}.default}
          file_server
        }
      '';
    };
  };
}
