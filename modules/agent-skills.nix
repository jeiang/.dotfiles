{
  inputs,
  lib,
  ...
}: let
  src = inputs.agent-skills;

  # install.sh writes this line, then a blank line, then the rendered profile.
  marker = "<!-- Managed by agent-skills; rerun the installer to update. -->";
  instructions = pkgs:
    pkgs.writeText "agent-skills-personal.md" ''
      ${marker}

      ${builtins.readFile "${src}/dist/instructions/personal.md"}'';

  namesOf = kind: dir: builtins.attrNames (lib.filterAttrs (_: t: t == kind) (builtins.readDir dir));

  skills = namesOf "directory" "${src}/shared";
  agentsFor = harness:
    lib.concatMap
    (dir: map (name: lib.nameValuePair name "${dir}/${name}") (namesOf "regular" dir))
    ["${src}/agents/${harness}" "${src}/dist/agents/${harness}"];

  # The clients write inside these directories themselves (Claude Code syncs
  # skills, Codex ships .system), so hjem owns the entries, never the directory.
  harness = root: harnessName:
    {
      "${root}" = {
        type = "directory";
        permissions = "0700";
      };
      "${root}/skills".type = "directory";
      "${root}/agents".type = "directory";
    }
    // lib.listToAttrs (map (name: lib.nameValuePair "${root}/skills/${name}" {source = "${src}/shared/${name}";}) skills)
    // lib.listToAttrs (map (a: lib.nameValuePair "${root}/agents/${a.name}" {source = a.value;}) (agentsFor harnessName));

  files = pkgs:
    harness ".claude" "claude"
    // harness ".codex" "codex"
    // {
      # Claude Code ignores a symlinked CLAUDE.md in Cowork sessions and refuses to edit through one.
      ".claude/CLAUDE.md" = {
        source = instructions pkgs;
        type = "copy";
        permissions = "0600";
      };
      ".codex/AGENTS.md" = {
        source = instructions pkgs;
        type = "copy";
        permissions = "0600";
      };
    };
in {
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
