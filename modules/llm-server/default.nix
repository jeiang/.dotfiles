{self, ...}: let
  llmPort = 8080;
  # PR #195 persists this path; renaming it would need another migrate-persist.
  llmWeightsDir = "/var/cache/bonsai-models";
  llmWeightsFile = "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
  llmWeightsUrl = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/${llmWeightsFile}";
  llmWeightsSha256 = "707a55a8a4397ecde44de0c499d3e68c1ad1d240d1da65826b4949d1043f4450";
  llmGpuTarget = "gfx1201";
  # The 22 GB of weights do not fit the 16 GB dGPU: the MoE experts of this
  # many layers stay on the CPU, which is what leaves headroom for a 65536
  # token q4_0 KV cache.
  llmCpuMoeLayers = 22;
in {
  flake.lib.llmServerPort = llmPort;

  nixos.modules.artemis = {
    lib,
    pkgs,
    ...
  }: let
    llmLlamaCpp = pkgs.llama-cpp.override {
      rocmSupport = true;
      rocmGpuTargets = [llmGpuTarget];
    };

    llmFetch = pkgs.writeShellApplication {
      name = "llm-server-fetch";
      runtimeInputs = [pkgs.curl pkgs.coreutils];
      text = ''
        dest="${llmWeightsDir}/${llmWeightsFile}"
        tmp="${llmWeightsDir}/.${llmWeightsFile}.part"
        trap 'rm -f "$tmp"' EXIT
        curl --fail --location --retry 3 --retry-delay 5 -o "$tmp" "${llmWeightsUrl}"
        printf '%s  %s\n' "${llmWeightsSha256}" "$tmp" | sha256sum --check --status
        mv "$tmp" "$dest"
      '';
    };
  in {
    # The model server and a game both want the whole dGPU.
    gaming.pauseUnits = ["llm-server.service"];

    users.groups.llm = {};
    users.users.llm = {
      isSystemUser = true;
      group = "llm";
    };

    systemd.services.llm-server-fetch =
      lib.recursiveUpdate
      {
        description = "Fetch and verify the LLM model weights";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        unitConfig.ConditionPathExists = "!${llmWeightsDir}/${llmWeightsFile}";
        serviceConfig = {
          Type = "oneshot";
          User = "llm";
          Group = "llm";
          ExecStart = lib.getExe llmFetch;
          # A ~22 GB download can run well past systemd's 90s start timeout.
          TimeoutStartSec = 0;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [llmWeightsDir];
          NoNewPrivileges = true;
        };
      }
      (self.lib.mountGuard llmWeightsDir {
        inherit pkgs;
        owner = "llm";
        mode = "0750";
      });

    systemd.services.llm-server =
      lib.recursiveUpdate
      {
        description = "llama-server (Qwen3.6-35B-A3B) on ROCm";
        after = ["llm-server-fetch.service" "network-online.target"];
        wants = ["network-online.target"];
        requires = ["llm-server-fetch.service"];
        wantedBy = ["multi-user.target"];
        environment.HIP_VISIBLE_DEVICES = "0";
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            "${llmLlamaCpp}/bin/llama-server"
            "-m"
            "${llmWeightsDir}/${llmWeightsFile}"
            "-ngl"
            "99"
            "-ncmoe"
            (toString llmCpuMoeLayers)
            "-fa"
            "1"
            "-c"
            "65536"
            "--cache-type-k"
            "q4_0"
            "--cache-type-v"
            "q4_0"
            "--jinja"
            "--reasoning"
            "off"
            # The model card's non-thinking sampling for general tasks.
            "--temp"
            "0.7"
            "--top-p"
            "0.8"
            "--top-k"
            "20"
            "--min-p"
            "0.0"
            "--presence-penalty"
            "1.5"
            "--host"
            "127.0.0.1"
            "--port"
            (toString llmPort)
          ];
          User = "llm";
          Group = "llm";
          SupplementaryGroups = ["video" "render"];
          Restart = "on-failure";
          RestartSec = 5;
          # The CPU-resident experts live in this process's RSS.
          MemoryMax = "40G";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = [llmWeightsDir];
          PrivateTmp = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      }
      (self.lib.mountGuard llmWeightsDir {
        inherit pkgs;
        owner = "llm";
        mode = "0750";
      });
  };
}
