{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    packages.omp = let
      strong = ["openai-codex/gpt-6.1-sol:high" "mistral/zai-glm-5-3:high"];
      light = "opencode-zen/deepseek-v4.1-flash-free:high";
      lightChain = [
        "opencode-zen/glm-5.3-flash-free:high"
        "mistral/deepseek-v4-1-flash-1017:high"
        "openai-codex/gpt-6.1-terra:low"
        "anthropic/claude-haiku-5-5:high"
      ];
      # An overlay, not a file in ~/.omp/agent: omp owns config.yml there and
      # rewrites it whenever a session changes a setting. PI_CONFIG_FILES
      # rather than --config, which only the launch, acp and models commands take.
      settings = (pkgs.formats.yaml {}).generate "omp-config.yml" {
        symbolPreset = "nerd";
        theme.dark = "dark-lunar";
        composer.shape = "claude";
        statusLine = {
          contextLine = "off";
          preset = "nerd";
          separator = "powerline-thin";
          transparent = true;
          compactThinkingLevel = true;
          sessionAccent = true;
        };
        display = {
          pinnedAgents = "full";
          showTurnTime = true;
          cacheMissMarker = true;
          subagentLivePreview = true;
          advisorCollapsedLines = 3;
        };
        composer.tokenRate = true;
        error.notify = "on";
        bash.gitGuard = true;
        github.enabled = true;
        marketplace.autoUpdate = "off";
        plan.autosave = true;
        btw.inject = true;
        gc.autoCompress = true;
        session.warnCost = 50;
        tools = {
          approvalMode = "yolo";
          xdevNotices = false;
          restrictedFolders = ["~/.ssh" "~/.gnupg" "~/.config/sops" "~/Library" "/etc"];
        };
        cycleOrder = ["smol" "default" "slow" "max-reasoning"];
        tier.subagent = "none";
        tui = {
          completeScrollback = true;
          codexResetFireworks = true;
        };
        startup.checkUpdate = false;
        secrets.enabled = true;
        lsp.diagnosticsOnEdit = true;
        astGrep.enabled = true;
        providers = {
          anthropic.slowMode = "auto";
          openaiLiveSteering = true;
        };
        # Paid OpenCode Zen models are off limits; only its free tier is used.
        # Mistral bills per token, so only the models placed in roles are enabled.
        enabledModels = [
          "anthropic/*"
          "openai-codex/*"
          "opencode-zen/*-free"
          "mistral/mistral-large-4"
          "mistral/deepseek-v4-1-flash-1017"
          "mistral/zai-glm-5-3"
          "mistral/zai-glm-5-3-flash"
        ];
        prewalk = {
          enabled = false;
          auto = "suggest";
          into = "anthropic/claude-sonnet-5-5:high";
        };
        # Only mnemopi reads the memory role; local uses the default and smol roles.
        memory.backend = "mnemopi";
        mnemopi = {
          scoping = "per-project-tagged";
          polyphonicRecall = true;
          proactiveLinking = true;
        };
        find.enabled = "on";
        task = {
          showResolvedModelBadge = true;
          enableEffort = false;
          file = true;
          perCallModel = "eval";
          perCallModelAllow = [
            "openai-codex/gpt-6.1-sol"
            "openai-codex/gpt-6.1-terra"
            "mistral/deepseek-v4-1-flash-1017"
            "anthropic/claude-sonnet-5-5"
          ];
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
          agentCompactionThresholdOverrides = {
            task = 200000;
            researcher = 200000;
            reviewer = 200000;
          };
        };
        advisor = {
          enabled = true;
          reviewMode = "agent-end";
          reviewInterval = 1;
        };
        compaction = {
          thresholdTokens = 400000;
          idleEnabled = true;
          idleThresholdTokens = 250000;
        };
        codexResets = {
          autoRedeem = "yes";
          keepCredits = 1;
        };
        claudeResets = {
          autoRedeem = "yes";
          keepCredits = 1;
        };
        modelRoles = {
          default = "anthropic/claude-opus-5-5:medium";
          slow = "anthropic/claude-opus-5-5:high";
          plan = "anthropic/claude-opus-5-5:high";
          max-reasoning = "anthropic/claude-opus-5-5:xhigh";
          advisor = "anthropic/claude-fable-5-2:low";
          task = "openai-codex/gpt-6.1-sol:medium";
          smol = "openai-codex/gpt-6.1-terra:high";
          fast = light;
          commit = light;
          widget = light;
          vision = light;
          memory = light;
          judge = "cloudflare-workers-ai/@cf/cloudflare/clef-flash";
          web = "openai-codex/gpt-6-luna:high";
        };
        retry = {
          usageAwareFallback = true;
          fallbackOn = "usage-limit";
          fallbackChains = {
            default = strong;
            slow = strong;
            plan = strong;
            max-reasoning = ["openai-codex/gpt-6.1-sol:xhigh" "mistral/zai-glm-5-3:xhigh"];
            advisor = ["openai-codex/gpt-6.1-sol:medium" "anthropic/claude-opus-5-5:medium" "mistral/deepseek-v4-1-flash-1017:max"];
            task = [
              "anthropic/claude-opus-5-5:medium"
              "mistral/zai-glm-5-3-flash:high"
              "mistral/deepseek-v4-1-flash-1017:max"
            ];
            smol = ["mistral/deepseek-v4-1-flash-1017:max" "anthropic/claude-sonnet-5-5:high"];
            fast = lightChain;
            commit = lightChain;
            widget = lightChain;
            memory = lightChain;
            judge = ["opencode-zen/jev-1.13-free" "@smol"];
            vision = [
              "mistral/mistral-large-4:medium"
              "openai-codex/gpt-6-luna:high"
              "anthropic/claude-haiku-5-5:high"
            ];
          };
        };
      };
      upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
      pinned = lib.importJSON ./hashes.json;
      src = upstream.src.override {
        tag = "v${pinned.version}";
        inherit (pinned) hash;
      };
    in
      inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        # llm-agents lags omp's releases; ./hashes.json and ./_bun.nix supply a newer release until llm-agents catches up.
        package =
          if lib.versionOlder upstream.version pinned.version
          then
            (upstream.override (prev: {
              bun2nixLib = prev.bun2nixLib // {fetchBunDeps = args: prev.bun2nixLib.fetchBunDeps (args // {bunNix = ./_bun.nix;});};
            })).overrideAttrs (prev: {
              inherit (pinned) version;
              inherit src;
              cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
                inherit src;
                name = "omp-${pinned.version}-cargo-vendor";
                hash = pinned.cargoHash;
              };
              # pi-shell and pi-natives target rustc 1.101, where VecDeque::is_empty is const and extern "C-unwind" fn items implement Fn; llm-agents builds with 1.99.
              postPatch =
                prev.postPatch
                + ''
                  substituteInPlace crates/pi-shell/src/bash/vm/proc.rs --replace-fail "pub const fn has_work" "pub fn has_work"
                  substituteInPlace crates/pi-natives/src/desktop/macos/session.rs --replace-fail "&online_displays(), CGDisplayIsAsleep)" "&online_displays(), |id| CGDisplayIsAsleep(id))"
                '';
            })
          else upstream;
        runShell = [
          "export PI_CONFIG_FILES=${settings}"
          # Deliberate retain/learn writes carry veracity "tool" (0.5), below auto-retained transcripts (0.8).
          "export MNEMOPI_TOOL_WEIGHT=1.0"
          # nixd, not nil: nil publishes nothing for a clean file, so omp waits out the diagnostics timeout. Suffix: the devshell's nixd still wins inside direnv.
          ''export PATH="$PATH:${pkgs.lib.makeBinPath [pkgs.nixd]}"''
        ];
      });
  };
}
