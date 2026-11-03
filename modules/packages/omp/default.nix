{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
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
        statusLine.contextLine = "off";
        display = {
          pinnedAgents = "full";
          showTurnTime = true;
          cacheMissMarker = true;
          subagentLivePreview = true;
        };
        composer.tokenRate = true;
        error.notify = "on";
        bash.gitGuard = true;
        github.enabled = true;
        marketplace.autoUpdate = "off";
        plan.autosave = true;
        cycleOrder = ["smol" "default" "slow" "max-reasoning"];
        tier.subagent = "none";
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
        compaction.thresholdTokens = 400000;
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
          fallbackOn = "usage-limit";
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
            judge = ["@smol"];
            vision = [
              "opencode-go/deepseek-v4.1-flash:high"
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
      # omp refuses to start on a Bun runtime older than 1.4.4; nixpkgs here and in llm-agents ships 1.4.2. Built from
      # llm-agents' nixpkgs so the embedded runtime shares ICU (Darwin) and glibc (Linux) with the rest of omp's closure.
      bun = inputs.llm-agents.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.bun.overrideAttrs {
        inherit (pinned.bun) version;
        src = pkgs.fetchurl pinned.bun.sources.${pkgs.stdenv.hostPlatform.system};
      };
    in
      inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        # llm-agents lags omp's releases; ./hashes.json and ./_bun.nix supply a newer release until llm-agents catches up.
        package =
          if lib.versionOlder upstream.version pinned.version
          then
            (upstream.override (prev: {
              inherit bun;
              # pi-builtins requires rustc 1.99; llm-agents' nixpkgs ships 1.98.
              inherit (pkgs) rustc cargo;
              rustPlatform =
                pkgs.rustPlatform
                // {
                  fetchCargoVendor = args:
                    pkgs.rustPlatform.fetchCargoVendor (args
                      // {
                        inherit src;
                        name = "omp-${pinned.version}-cargo-vendor";
                        hash = pinned.cargoHash;
                      });
                };
              bun2nixLib = prev.bun2nixLib // {fetchBunDeps = args: prev.bun2nixLib.fetchBunDeps (args // {bunNix = ./_bun.nix;});};
            })).overrideAttrs (prev: {
              inherit (pinned) version;
              inherit src;
              # bun2nix's hook installs node_modules with its own bun 1.4.2: bun 1.4.4 re-extracts some packages into
              # the read-only cache and fails. bun build --compile embeds the bun that runs it, so the build runs 1.4.4.
              preBuild = (prev.preBuild or "") + ''export PATH="${bun}/bin:$PATH"'';
              # llm-agents' buildPhase runs build-tool-views.ts, which this release lacks: exports load a hosted viewer pinned by the committed viewer.generated.json.
              buildPhase = lib.replaceStrings ["bun --cwd packages/collab-web scripts/build-tool-views.ts"] [""] prev.buildPhase;
            })
          else upstream;
        runShell = [
          "export PI_CONFIG_FILES=${settings}"
          # Deliberate retain/learn writes carry veracity "tool" (0.5), below auto-retained transcripts (0.8).
          "export MNEMOPI_TOOL_WEIGHT=1.0"
          # Suffix: the devshell's nil still wins inside direnv.
          ''export PATH="$PATH:${pkgs.lib.makeBinPath [pkgs.nil]}"''
        ];
      });
  };
}
