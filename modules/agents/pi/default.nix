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

  # Strata on artemis; zakkart reaches it through `ssh -L 8095:127.0.0.1:8095 artemis.jeiang.vpn`.
  models.providers.strata = {
    name = "Strata (artemis)";
    baseUrl = "http://127.0.0.1:${toString self.lib.strataPort}/v1";
    api = "openai-completions";
    # Strata needs no key; pi lists a provider only once it has one.
    apiKey = "strata";
    compat = {
      supportsReasoningEffort = true;
      thinkingFormat = "openai";
    };
    models = [
      {
        id = self.lib.strataModelName;
        name = "Inkling 2 Mini";
        reasoning = true;
        # Inkling's chat template accepts these reasoning_effort values; none still reasons a little.
        thinkingLevelMap = {
          off = "none";
          minimal = "minimal";
          low = "low";
          medium = "medium";
          high = "high";
          xhigh = "xhigh";
          max = "max";
        };
        input = ["text"];
        contextWindow = self.lib.strataMaxContext;
        maxTokens = 32768;
        cost = {
          input = 0;
          output = 0;
          cacheRead = 0;
          cacheWrite = 0;
        };
      }
    ];
  };

  advisor = {
    models = ["anthropic/claude-fable-5-2:medium" "openai-codex/gpt-6.1-sol:medium" "anthropic/claude-opus-5-5:medium" "mistral/deepseek-v4-1-flash-1017:max"];
  };

  language = languageId: extensions: {inherit languageId extensions;};
  # A catalog server runs under pi-devshell-exec: inside the devshell of its root (a worktree's own)
  # and, when that lacks the command, from nixpkgs. pi-lsp starts a server on the first file of its
  # language, so an unused entry costs nothing and the pi closure carries none of them.
  fromNix = attr: command: args: {
    command = "pi-devshell-exec";
    args = [command] ++ args;
    environment.PI_LSP_NIX = attr;
  };

  # pi rewrites settings.json when a session changes a setting, so it is a copy.
  settings = pkgs: {
    defaultProvider = "chain";
    defaultModel = "strong";
    # bash stays callable from codemode; the shell tool runs processes. pi starts grep inactive.
    defaultTools = ["-bash" "+codemode" "+grep"];
    # The codemode extension in pi-extensions wraps the built-in one.
    extensions = ["-builtin:codemode"];
    # Scripts find the declarations left out with searchTools(); the rarely used lsp_* ones fill the rest.
    codemode = {
      mode = "on";
      inlineBudget = 1500;
    };
    enableInstallTelemetry = false;
    # Mid-run compaction, which does not stop the run (the chains' compactAt waits for the run to
    # end). pi keys this by the session model and compacts at the answering target's window minus
    # the reserve, so a reserve must stay below the smallest window of its chain: 500k for
    # gpt-6.1-sol, 272k for gpt-6-luna. That gives 200k on those and 700k to 928k on the 1M models.
    compaction.modelOverrides = {
      "chain/strong".reserveTokens = 300000;
      "chain/light".reserveTokens = 72000;
      "chain/task".reserveTokens = 300000;
    };
    # The first start of a catalog server can fetch it from the binary cache.
    lsp.timeouts.initializeMs = 180000;
    # pi-lsp ships no server catalog. nixd, yaml, and bash are on the wrapper's PATH: almost every session uses them.
    lsp.servers = {
      rust =
        fromNix "rust-analyzer" "rust-analyzer" []
        // {
          rootMarkers = ["Cargo.toml"];
          languages = [(language "rust" [".rs"])];
        };
      zig =
        fromNix "zls" "zls" []
        // {
          rootMarkers = ["build.zig"];
          languages = [(language "zig" [".zig" ".zon"])];
        };
      go =
        fromNix "gopls" "gopls" []
        // {
          rootMarkers = ["go.mod"];
          languages = [(language "go" [".go"])];
        };
      typescript =
        fromNix "typescript-language-server" "typescript-language-server" ["--stdio"]
        // {
          rootMarkers = ["tsconfig.json" "package.json"];
          languages = [
            (language "typescript" [".ts" ".mts" ".cts"])
            (language "typescriptreact" [".tsx"])
            (language "javascript" [".js" ".mjs" ".cjs"])
            (language "javascriptreact" [".jsx"])
          ];
        };
      clangd =
        fromNix "clang-tools" "clangd" []
        // {
          rootMarkers = ["compile_commands.json" "CMakeLists.txt"];
          languages = [
            (language "c" [".c" ".h"])
            (language "cpp" [".cc" ".cpp" ".cxx" ".hh" ".hpp" ".hxx"])
          ];
        };
      kotlin =
        fromNix "kotlin-language-server" "kotlin-language-server" []
        // {
          rootMarkers = ["settings.gradle.kts" "build.gradle.kts"];
          languages = [(language "kotlin" [".kt" ".kts"])];
        };
      swift =
        (
          # The nixpkgs build does not know the iOS SDK; the Xcode toolchain's server does.
          if pkgs.stdenv.hostPlatform.isDarwin
          then {
            command = "xcrun";
            args = ["sourcekit-lsp"];
          }
          else fromNix "sourcekit-lsp" "sourcekit-lsp" []
        )
        // {
          rootMarkers = ["Package.swift"];
          languages = [(language "swift" [".swift"])];
        };
      python =
        fromNix "basedpyright" "basedpyright-langserver" ["--stdio"]
        // {
          rootMarkers = ["pyproject.toml"];
          languages = [(language "python" [".py"])];
        };
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

  # The agents in pi-extensions load their extensions by these names.
  ownExtensions = ["advisor" "chains" "codemode" "emphasis" "footer" "github" "guards" "images" "lint" "loadout" "nix" "papercuts" "plan" "server-compaction" "skill-mentions" "turn-time" "usage" "workspace"];

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
        "todo.ts" = "${examples}/todo.ts";
        "questionnaire.ts" = "${examples}/questionnaire.ts";
      };
    # The instructions, agents, and pi's own skills live with the extensions they describe.
    own = kind:
      lib.mapAttrs' (name: _: lib.nameValuePair "${home}/${kind}/${name}" {source = "${piExtensions}/${kind}/${name}";})
      (builtins.readDir "${inputs.pi-extensions}/${kind}");
  in {
    environment.systemPackages = [self.packages.${system}.pi];

    hjem.users.${self.lib.facts.userName}.files =
      {
        "${home}/settings.json" = {
          source = json pkgs "pi-settings.json" (settings pkgs);
          type = "copy";
          permissions = "0600";
        };
        "${home}/chains.json".source = json pkgs "chains.json" chains;
        "${home}/advisor.json".source = json pkgs "advisor.json" advisor;
        "${home}/models.json".source = json pkgs "models.json" models;
        "${home}/loadout.json".source = json pkgs "loadout.json" loadout;
        "${home}/subagent.json".source = json pkgs "subagent.json" {maxConcurrent = 3;};
        # pi rewrites mcp.json when /mcp changes exposure; sign in once with `pi mcp login superlogical` (Rex Beta Discord).
        "${home}/mcp.json" = {
          source = json pkgs "mcp.json" {
            mcpServers.superlogical = {
              url = "https://www.superlogical.com/rex/community-mcp";
              description = "Rex documentation, changelog, and Rex Beta Discord discussions";
            };
          };
          type = "copy";
          permissions = "0600";
        };
        # pi-lens formats, autofixes, and guards reads by default; only its diagnostics are wanted.
        ".pi-lens/config.json".source = json pkgs "pi-lens.json" {
          format.enabled = false;
          autofix.enabled = false;
          readGuard.enabled = false;
          widget.visible = false;
        };
        ".pi-lens/rules/ast-grep-rules/rules/nix.yml".source = ./nix-rules.yml;
        "${home}/AGENTS.md".source = "${piExtensions}/prompts/AGENTS.md";
      }
      // lib.mapAttrs' (name: source: lib.nameValuePair "${home}/extensions/${name}" {inherit source;}) extensions
      // own "agents"
      // own "skills";
  };

  nixos.modules.workstation.persistence.cache.directories = [".pi-lens"];
}
