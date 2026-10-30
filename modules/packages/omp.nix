{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.omp = let
      strong = ["opencode-go/kimi-k3.1-pro:high" "openai-codex/gpt-6.1-sol:high"];
      light = "opencode-zen/deepseek-v4.1-flash-free:high";
      lightChain = [
        "opencode-zen/glm-5.3-flash-free:high"
        "opencode-go/deepseek-v4.1-flash:high"
        "openai-codex/gpt-6.1-terra:low"
        "anthropic/claude-haiku-5-5:high"
      ];
      # An overlay, not a file in ~/.omp/agent: omp owns config.yml there and
      # rewrites it whenever a session changes a setting. PI_CONFIG_FILES
      # rather than --config, which only the launch, acp and models commands take.
      settings = (pkgs.formats.yaml {}).generate "omp-config.yml" {
        tools.approvalMode = "yolo";
        symbolPreset = "nerd";
        theme.dark = "dark-tundra";
        composer.shape = "band";
        display.pinnedAgents = "full";
        display.showTurnTime = true;
        tui.completeScrollback = true;
        startup.checkUpdate = false;
        secrets.enabled = true;
        lsp.diagnosticsOnEdit = true;
        astGrep.enabled = true;
        providers = {
          anthropic.slowMode = "auto";
          maxInFlightRequests.opencode-go = 8;
        };
        # Paid OpenCode Zen models are off limits; only its free tier is used.
        enabledModels = ["anthropic/*" "openai-codex/*" "opencode-go/*" "opencode-zen/*-free"];
        prewalk.enabled = true;
        memory.backend = "local";
        find.enabled = "on";
        task = {
          showResolvedModelBadge = true;
          enableEffort = false;
          agentModelOverrides = {
            researcher = "@task";
            reviewer = "@task";
            security-reviewer = "@slow";
            change-reviewer = "@task";
            designer = "@task";
            scout = "@smol";
            sonic = "@smol";
          };
          softRequestBudget = 150;
          agentSoftRequestBudget = {
            change-reviewer = 100;
            reviewer = 100;
            researcher = 80;
            security-reviewer = 80;
          };
          agentCompactionThresholdOverrides.task = 200000;
        };
        advisor = {
          enabled = true;
          reviewInterval = 5;
        };
        compaction.thresholdTokens = 400000;
        codexResets.autoRedeem = "no";
        claudeResets.autoRedeem = "no";
        modelRoles = {
          default = "anthropic/claude-opus-5-5:medium";
          slow = "anthropic/claude-opus-5-5:high";
          plan = "anthropic/claude-opus-5-5:high";
          max-reasoning = "anthropic/claude-opus-5-5:xhigh";
          advisor = "openai-codex/gpt-6.1-sol:medium";
          task = "openai-codex/gpt-6.1-sol:medium";
          smol = "openai-codex/gpt-6.1-terra:high";
          fast = light;
          commit = light;
          widget = light;
          vision = light;
          memory = light;
          judge = "opencode-zen/jev-1.13-free";
          web = "openai-codex/gpt-6-luna:high";
        };
        retry = {
          usageAwareFallback = true;
          fallbackChains = {
            default = strong;
            slow = strong;
            plan = strong;
            max-reasoning = [
              "opencode-go/kimi-k3.1-pro:max"
              "openai-codex/gpt-6.1-sol:xhigh"
              "opencode-go/gemini-4-argon:high"
            ];
            advisor = ["opencode-go/kimi-k3.1-pro:high" "anthropic/claude-opus-5-5:medium"];
            task = [
              "opencode-go/kimi-k3.1-pro:high"
              "opencode-go/deepseek-v4.1-flash:max"
              "anthropic/claude-opus-5-5:medium"
            ];
            smol = ["opencode-go/deepseek-v4.1-flash:max" "anthropic/claude-sonnet-5-5:high"];
            fast = lightChain;
            commit = lightChain;
            widget = lightChain;
            memory = lightChain;
            judge = [];
            vision = [
              "opencode-go/deepseek-v4.1-flash:high"
              "openai-codex/gpt-6-luna:high"
              "anthropic/claude-haiku-5-5:high"
            ];
          };
        };
      };
    in
      inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
        runShell = [''export PI_CONFIG_FILES=${settings}''];
      });
  };
}
