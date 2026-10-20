{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.omp = let
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
        startup.checkUpdate = false;
        secrets.enabled = true;
        lsp.diagnosticsOnEdit = true;
        astGrep.enabled = true;
        providers.anthropic.serverSideFallback = true;
        task = {
          showResolvedModelBadge = true;
          enableEffort = false;
          agentModelOverrides = {
            researcher = "openai-codex/gpt-6-luna:xhigh";
            security-reviewer = "@slow";
            change-reviewer = "@task";
            designer = "@task";
            scout = "@smol:medium";
            sonic = "@smol:medium";
          };
        };
        advisor.enabled = true;
        codexResets.autoRedeem = "no";
        claudeResets.autoRedeem = "no";
        modelRoles = {
          default = "anthropic/claude-opus-5-5:medium";
          task = "anthropic/claude-sonnet-5-5:medium";
          fast = "anthropic/claude-haiku-5-5:high";
          smol = "openai-codex/gpt-6-luna:high";
          slow = "anthropic/claude-opus-5-5:medium";
          max-reasoning = "anthropic/claude-fable-5-1:medium";
          advisor = "anthropic/claude-fable-5-1:low";
          commit = "openai-codex/gpt-6-luna:high";
          web = "openai-codex/gpt-6-luna:high";
        };
        retry.fallbackChains = {
          default = ["openai-codex/gpt-6.1-sol:high"];
          task = ["openai-codex/gpt-6-luna:high"];
          fast = ["openai-codex/gpt-6-luna:high"];
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
