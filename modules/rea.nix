{
  self,
  lib,
  ...
}: let
  skill = "reverse-engineer-anything";

  rea = {
    config,
    pkgs,
  }: let
    package = self.packages.${pkgs.stdenv.hostPlatform.system}.rea;
  in {
    environment.systemPackages = [package];

    # From the package, not agent-skills: the skill describes this release's MCP tool catalog.
    hjem.users.${config.preferences.user.name}.files = lib.mapAttrs' (_: root:
      lib.nameValuePair "${root}/skills/${skill}" {
        source = "${package}/lib/node_modules/rea-agents/skills/${skill}";
      })
    self.lib.agentHomes;
  };
in {
  nixos.modules.artemis = {
    config,
    pkgs,
    ...
  }:
    rea {inherit config pkgs;};

  darwin.modules.base = {
    config,
    pkgs,
    ...
  }:
    rea {inherit config pkgs;}
    // {
      homebrew.brews = ["ghidra"];
    };
}
