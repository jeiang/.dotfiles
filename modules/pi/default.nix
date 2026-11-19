{
  self,
  inputs,
  lib,
  ...
}: let
  home = self.lib.agentHomes.pi;
  json = pkgs: name: value: (pkgs.formats.json {}).generate name value;

  chains = {
    chains = {
      strong = {
        targets = ["anthropic/claude-opus-5-5:medium" "openai-codex/gpt-6.1-sol:high"];
        compactAt = 400000;
      };
      light = {
        targets = ["openai-codex/gpt-6-luna:xhigh" "anthropic/claude-haiku-5-5:xhigh"];
        compactAt = 200000;
      };
      task = {
        targets = ["openai-codex/gpt-6.1-sol:high" "mistral/deepseek-v4-1-flash-1017:high" "anthropic/claude-sonnet-5-5:high"];
        compactAt = 200000;
      };
    };
  };

  advisor = {
    models = ["anthropic/claude-fable-5-2:low" "openai-codex/gpt-6.1-sol:medium" "anthropic/claude-opus-5-5:medium" "mistral/deepseek-v4-1-flash-1017:max"];
  };

  # pi rewrites settings.json when a session changes a setting, so it is a copy.
  settings = {
    defaultProvider = "chain";
    defaultModel = "strong";
    # bash stays callable from codemode; the shell tool runs processes.
    defaultTools = ["-bash" "+codemode"];
    codemode.mode = "on";
    enableInstallTelemetry = false;
    # pi-lsp ships no server catalog; these binaries are on the wrapper's PATH.
    lsp.servers = {
      nix = {
        command = "nixd";
        args = [];
        languages = [
          {
            extensions = [".nix"];
            languageId = "nix";
          }
        ];
      };
      yaml = {
        command = "yaml-language-server";
        args = ["--stdio"];
        languages = [
          {
            extensions = [".yaml" ".yml"];
            languageId = "yaml";
          }
        ];
      };
      bash = {
        command = "bash-language-server";
        args = ["start"];
        languages = [
          {
            extensions = [".sh" ".bash"];
            languageId = "shellscript";
          }
        ];
      };
    };
  };

  # Agents from agent-skills load their extensions by these names.
  ownExtensions = ["advisor" "chains" "emphasis" "github" "guards" "images" "lint" "loadout" "turn-time" "workspace"];

  # Direct in the tool list: file tools, shell, github, todo, questionnaire, subagent, advise, and pi-lsp navigation.
  loadout.hidden = [
    "lsp_status"
    "lsp_document_symbols"
    "lsp_workspace_symbols"
    "lsp_rename"
    "lsp_code_actions"
    "lsp_apply"
    "web_search"
    "source_check"
    "fetch_content"
    "get_search_content"
    "lens_diagnostics"
    "symbol_search"
    "effective_config"
    "project_report"
    "module_report"
    "read_symbol"
    "read_enclosing"
    "pi_lens_activate_tools"
  ];
in {
  shared.modules.workstation = {pkgs, ...}: let
    inherit (pkgs.stdenv.hostPlatform) system;
    piExtensions = inputs.pi-extensions.packages.${system}.default;
    examples = "${inputs.llm-agents.packages.${system}.pi}/libexec/pi/examples/extensions";
    extensions =
      lib.genAttrs ownExtensions (name: "${piExtensions}/extensions/${name}")
      // {
        pi-lens = "${piExtensions}/node_modules/pi-lens";
        pi-lsp = "${piExtensions}/node_modules/@ian-pascoe/pi-lsp";
        pi-web-access = "${piExtensions}/node_modules/pi-web-access";
        pi-subagents = self.packages.${system}.pi-subagents;
        "todo.ts" = "${examples}/todo.ts";
        "questionnaire.ts" = "${examples}/questionnaire.ts";
      };
  in {
    environment.systemPackages = [self.packages.${system}.pi];

    hjem.users.${self.lib.facts.userName}.files =
      {
        "${home}/settings.json" = {
          source = json pkgs "pi-settings.json" settings;
          type = "copy";
          permissions = "0600";
        };
        "${home}/chains.json".source = json pkgs "chains.json" chains;
        "${home}/advisor.json".source = json pkgs "advisor.json" advisor;
        "${home}/loadout.json".source = json pkgs "loadout.json" loadout;
        "${home}/extensions/subagent/config.json".source = json pkgs "pi-subagents.json" {
          worktreeBaseDir = ".worktrees";
          worktreeProvider = "native";
        };
        # pi-lens formats, autofixes, and guards reads by default; only its diagnostics are wanted.
        ".pi-lens/config.json".source = json pkgs "pi-lens.json" {
          format.enabled = false;
          autofix.enabled = false;
          readGuard.enabled = false;
        };
        ".pi-lens/rules/ast-grep-rules/rules/nix.yml".source = ./nix-rules.yml;
      }
      // lib.mapAttrs' (name: source: lib.nameValuePair "${home}/extensions/${name}" {inherit source;}) extensions;
  };

  nixos.modules.artemis.persistence.cache.directories = [".pi-lens"];
}
