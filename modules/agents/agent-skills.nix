{
  self,
  inputs,
  lib,
  ...
}: let
  profile = "personal";
  homes = {
    pi = ".pi/agent";
  };

  # The REA tool is not installed on this host, so its skill has nothing to drive.
  droppedSkills = ["reverse-engineer-anything"];

  # pi takes only skills from agent-skills. Its instructions, agents, and own skills come from
  # pi-extensions (modules/agents/pi), and a skill of the same name there replaces the shared one.
  ownSkills = name: lib.optionals (name == "pi") (builtins.attrNames (builtins.readDir "${inputs.pi-extensions}/skills"));

  # The clients write inside these directories themselves, so hjem owns the entries, never the directory.
  harness = pkgs: root: name: let
    entries = inputs.agent-skills.lib.entries.${name}.${profile};
    tree = inputs.agent-skills.packages.${pkgs.stdenv.hostPlatform.system}."${name}-${profile}";
    links = kind: names:
      lib.listToAttrs (map
        (entry:
          lib.nameValuePair "${root}/${kind}/${entry}" {
            source = "${tree}/${kind}/${entry}";
          })
        names);
  in
    {
      "${root}" = {
        type = "directory";
        permissions = "0700";
      };
      "${root}/skills".type = "directory";
      "${root}/agents".type = "directory";
    }
    // links "skills" (lib.subtractLists (droppedSkills ++ ownSkills name) entries.skills)
    // links "agents" (entries.agents or [])
    // lib.optionalAttrs (entries ? instructions) {
      "${root}/${entries.instructions}" = {
        source = "${tree}/${entries.instructions}";
        type = "copy";
        permissions = "0600";
      };
    }
    // lib.optionalAttrs (entries ? rules) {
      "${root}/${entries.rules}".source = "${tree}/${entries.rules}";
    };

  files = pkgs: lib.concatMapAttrs (name: root: harness pkgs root name) homes;
in {
  flake.lib.agentHomes = homes;

  shared.modules.workstation = {pkgs, ...}: {
    hjem.users.${self.lib.facts.userName}.files = files pkgs;
  };

  # The home holds OAuth tokens: persisted, never in the backup allowlist.
  # .claude stays: Claude Code is still installed (modules/agents/claude-code.nix) and keeps its login there.
  nixos.modules.workstation.persistence.data.directories = map (directory: {
    inherit directory;
    mode = "0700";
  }) (lib.attrValues homes ++ [".claude"]);
}
