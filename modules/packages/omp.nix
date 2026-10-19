{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.omp = let
      # An overlay, not a file in ~/.omp/agent: omp owns config.yml there and
      # rewrites it whenever a session changes a setting. PI_CONFIG_FILES
      # rather than --config, which only the launch, acp and models commands take.
      settings = (pkgs.formats.yaml {}).generate "omp-config.yml" {
        tools.approvalMode = "yolo";
        display.pinnedAgents = "full";
        display.showTurnTime = true;
        startup.checkUpdate = false;
        secrets.enabled = true;
        task.showResolvedModelBadge = true;
        task.agentModelOverrides = {
          researcher = "@researcher";
          security-reviewer = "@slow";
          change-reviewer = "anthropic/claude-sonnet-5-5:high";
          designer = "anthropic/claude-sonnet-5-5:high";
        };
        advisor.enabled = true;
        codexResets.autoRedeem = "no";
        modelRoles = {
          fast = "anthropic/claude-haiku-5-5:high";
          smol = "openai-codex/gpt-6-luna:high";
          researcher = "openai-codex/gpt-6-luna:max";
          slow = "anthropic/claude-opus-5-5:medium";
          max-reasoning = "anthropic/claude-fable-5-1:medium";
          advisor = "anthropic/claude-fable-5-1:medium";
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
