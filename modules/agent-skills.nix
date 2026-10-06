{
  inputs,
  lib,
  ...
}: let
  profile = "personal";
  homes = {
    claude = ".claude";
    codex = ".codex";
    omp = ".omp/agent";
  };

  # The clients write inside these directories themselves (Claude Code syncs
  # skills, Codex ships .system), so hjem owns the entries, never the directory.
  harness = pkgs: root: name: let
    entries = inputs.agent-skills.lib.entries.${name}.${profile};
    tree = inputs.agent-skills.packages.${pkgs.stdenv.hostPlatform.system}."${name}-${profile}";
    links = kind:
      lib.listToAttrs (map
        (entry:
          lib.nameValuePair "${root}/${kind}/${entry}" {
            source = "${tree}/${kind}/${entry}";
          })
        entries.${kind});
  in
    {
      "${root}" = {
        type = "directory";
        permissions = "0700";
      };
      "${root}/skills".type = "directory";
      "${root}/agents".type = "directory";

      # Claude Code ignores a symlinked CLAUDE.md in Cowork sessions and refuses to edit through one.
      "${root}/${entries.instructions}" = {
        source = "${tree}/${entries.instructions}";
        type = "copy";
        permissions = "0600";
      };
    }
    // links "skills"
    // links "agents";

  files = pkgs: lib.concatMapAttrs (name: root: harness pkgs root name) homes;
in {
  flake.lib.agentHomes = homes;

  nixos.modules.artemis = {
    config,
    pkgs,
    ...
  }: {
    hjem.users.${config.preferences.user.name}.files = files pkgs;

    persistence.data.directories = [
      {
        directory = ".codex";
        mode = "0700";
      }
    ];
  };

  darwin.modules.base = {
    config,
    pkgs,
    ...
  }: {
    hjem.users.${config.preferences.user.name}.files = files pkgs;
  };
}
