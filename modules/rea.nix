{
  self,
  lib,
  ...
}: let
  skill = "reverse-engineer-anything";
in {
  shared.modules.workstation = {pkgs, ...}: let
    package = self.packages.${pkgs.stdenv.hostPlatform.system}.rea;
  in {
    environment.systemPackages = [package];

    # From the package, not agent-skills: the skill describes this release's MCP tool catalog.
    hjem.users.${self.lib.facts.userName}.files = lib.mapAttrs' (_: root:
      lib.nameValuePair "${root}/skills/${skill}" {
        source = "${package}/lib/node_modules/rea-agents/skills/${skill}";
      })
    self.lib.agentHomes;
  };
}
