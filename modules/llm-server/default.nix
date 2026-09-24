{self, ...}: let
  llmPort = 8080;
  # PR #195 persists this path; renaming it would need another migrate-persist.
  llmWeightsDir = "/var/cache/bonsai-models";
  # The MTP repository ships its file under the same name as the plain one,
  # so the local name differs to force a fetch.
  llmWeightsFile = "Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL.gguf";
  llmMmprojFile = "Qwen3.6-35B-A3B-MTP-mmproj-F16.gguf";
  llmRepo = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/resolve/main";
  llmFiles = {
    ${llmWeightsFile} = {
      url = "${llmRepo}/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf";
      sha256 = "55983c5a75a1ab969824077b3bb3de4146e82a9234072b48ad4e8f92ad3fe9f1";
    };
    ${llmMmprojFile} = {
      url = "${llmRepo}/mmproj-F16.gguf";
      sha256 = "71f3cbc1f7cc0f30d09d41cfa924c0060827ebc33bf15ace7e86661e856f0160";
    };
  };
  # Only 10 of the 40 layers keep a per-token KV cache, so 131072 tokens at
  # q8_0 is about 1.3 GiB.
  llmContextLength = 131072;
  # The 23 GB of weights do not fit the 16 GB dGPU: the MoE experts of this
  # many layers stay on the CPU, which also leaves VRAM headroom for a full
  # context with an image.
  llmCpuMoeLayers = 24;
in {
  flake.lib = {
    llmServerPort = llmPort;
    llmServerContextLength = llmContextLength;
    # llama-server reports this as the model id on /v1/models with no --alias
    # set; a single-model server ignores whatever "model" a client requests.
    llmServerModelId = llmWeightsFile;
  };

  nixos.modules.artemis = {
    lib,
    pkgs,
    ...
  }: let
    llmLlamaCpp = pkgs.llama-cpp.override {
      rocmSupport = true;
      rocmGpuTargets = [self.lib.artemisDgpuTarget];
    };

    # Fetches what is missing, then deletes any other .gguf so a model swap
    # does not leave the old weights on disk.
    llmFetch = pkgs.writeShellApplication {
      name = "llm-server-fetch";
      runtimeInputs = [pkgs.curl pkgs.coreutils pkgs.findutils];
      text =
        lib.concatStrings (lib.mapAttrsToList (file: src: ''
            if [ ! -e "${llmWeightsDir}/${file}" ]; then
              tmp="${llmWeightsDir}/.${file}.part"
              trap 'rm -f "$tmp"' EXIT
              curl --fail --location --retry 3 --retry-delay 5 -o "$tmp" "${src.url}"
              printf '%s  %s\n' "${src.sha256}" "$tmp" | sha256sum --check --status
              mv "$tmp" "${llmWeightsDir}/${file}"
            fi
          '')
          llmFiles)
        + ''
          find "${llmWeightsDir}" -maxdepth 1 -name '*.gguf' ${lib.concatMapStringsSep " " (file: "! -name ${lib.escapeShellArg file}") (builtins.attrNames llmFiles)} -delete
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
        # "|" makes the conditions OR: a fetch runs when any file is missing.
        unitConfig.ConditionPathExists = map (file: "|!${llmWeightsDir}/${file}") (builtins.attrNames llmFiles);
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
        description = "llama-server (Qwen3.6-35B-A3B MTP) on ROCm";
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
            "--mmproj"
            "${llmWeightsDir}/${llmMmprojFile}"
            "-ngl"
            "99"
            "-ncmoe"
            (toString llmCpuMoeLayers)
            "-fa"
            "1"
            "-c"
            (toString llmContextLength)
            "--cache-type-k"
            "q8_0"
            "--cache-type-v"
            "q8_0"
            # Plain reads instead of mmap: the CPU experts are tensor
            # overrides, which llama-server loads faster this way.
            "--load-mode"
            "none"
            # The weights carry multi-token-prediction heads. An explicit
            # slot count turns off the automatic unified KV, hence -kvu.
            "--spec-type"
            "draft-mtp"
            "--spec-draft-n-max"
            "2"
            "-np"
            "2"
            "-kvu"
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
