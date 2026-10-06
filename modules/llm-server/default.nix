{self, ...}: let
  llmPort = 8080;
  # PR #195 persists this path; renaming it would need another migrate-persist.
  llmWeightsDir = "/var/cache/bonsai-models";
  # A subdirectory, so a rollback's fetch (which deletes every top-level
  # .gguf it does not list) leaves these weights alone.
  strataDir = "${llmWeightsDir}/strata";
  llmRepo = "https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/resolve/main";
  llmShardFile = n: "Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-0000${toString n}-of-00002.gguf";
  llmMmprojFile = "mmproj-Qwen3.8-Flash-Next-BF16.gguf";
  llmFiles = {
    ${llmShardFile 1} = {
      url = "${llmRepo}/IQ2_XS/${llmShardFile 1}";
      sha256 = "92cee27ae5bbadcd732416a0f7a7f0acc092399dbbe8f5a5efa707c2ec0a49d7";
    };
    # The n-gram table, read from the SSD while the model answers.
    ${llmShardFile 2} = {
      url = "${llmRepo}/IQ2_XS/${llmShardFile 2}";
      sha256 = "316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113";
    };
    ${llmMmprojFile} = {
      url = "${llmRepo}/${llmMmprojFile}";
      sha256 = "b1a82259702816a5330d7bd7607cd9676b11780e79ff7348c21103ff3ce49bd0";
    };
  };
  llmContextLength = 131072;
  # Strata answers to any model name and lists this one on /v1/models.
  llmModelName = "qwen3.8-flash-next-iq2_xs";
in {
  flake.lib = {
    llmServerPort = llmPort;
    llmServerContextLength = llmContextLength;
    llmServerModelId = llmModelName;
  };

  nixos.modules.artemis = {
    lib,
    pkgs,
    ...
  }: let
    strata = self.packages.${pkgs.stdenv.hostPlatform.system}.strata;
    shard = n: "${strataDir}/${llmShardFile n}";
    # The pack and the MTP runtime are derived from the weights by this
    # Strata version's tools, so a Strata bump rebuilds them.
    pack = "${strataDir}/packs/iq2_xs-${strata.version}";
    mtp = "${strataDir}/mtp";
    mtpRuntime = "${mtp}/rt-${strata.version}";

    llmFetch = pkgs.writeShellApplication {
      name = "llm-server-fetch";
      runtimeInputs = [pkgs.curl pkgs.coreutils pkgs.findutils strata];
      text =
        ''
          mkdir -p "${strataDir}"
        ''
        + lib.concatStrings (lib.mapAttrsToList (file: src: ''
            if [ ! -e "${strataDir}/${file}" ]; then
              tmp="${strataDir}/.${file}.part"
              curl --fail --location --retry 3 --retry-delay 5 --continue-at - -o "$tmp" "${src.url}"
              printf '%s  %s\n' "${src.sha256}" "$tmp" | sha256sum --check --status
              mv "$tmp" "${strataDir}/${file}"
            fi
          '')
          llmFiles)
        + ''
          # Weights of earlier models: the llama-server ones at the top level
          # and any other model here.
          find "${llmWeightsDir}" -maxdepth 1 -name '*.gguf' -delete
          find "${strataDir}" -maxdepth 1 -name '*.gguf' ${lib.concatMapStringsSep " " (file: "! -name ${lib.escapeShellArg file}") (builtins.attrNames llmFiles)} -delete

          if [ ! -e "${pack}/.done" ]; then
            rm -rf "${strataDir}/packs"
            strata-tool iq_pack.py --gguf "${shard 1}" --out "${pack}"
            touch "${pack}/.done"
          fi

          if [ ! -e "${mtpRuntime}/.done" ]; then
            strata-tool mtp_fetch.py fetch --out "${mtp}"
            strata-tool mtp_pack.py --src "${mtp}" --experts q2_0 --out "${mtp}/mtp-q2_0.gguf"
            rm -rf "${mtp}"/rt-*
            strata-tool mtp_rt.py --gguf "${mtp}/mtp-q2_0.gguf" --out "${mtpRuntime}"
            cp ${strata}/share/strata/data/draft_vocab.bin "${mtpRuntime}/draft_vocab.bin"
            touch "${mtpRuntime}/.done"
          fi
        '';
    };

    # setup.py's run config for this machine: 8-bit KV streamed from RAM past
    # 32K positions, so the VRAM holds more experts, and MTP drafting.
    strataConfig = {
      exe = "${strata}/bin/strata";
      args = [
        "--pack"
        pack
        "--native"
        (shard 1)
        "--ple-gguf"
        (shard 2)
        "--expert-profile"
        "${strata}/share/strata/data/expert-profile.bin"
        "--expert-cache"
        "auto"
        "--prefill"
        "auto"
        "--spec"
        "4"
        "--spec-min-p"
        "0.5"
        "--mtp"
        mtpRuntime
        "--max-context"
        (toString llmContextLength)
        "--kv"
        "int8"
        "--kv-resident"
        "32768"
        # Parks Hermes's conversation while a background review or summary
        # runs, so the next turn does not read the whole prompt again.
        "--conversation-cache-mib"
        "8192"
        "--conversation-cache-slots"
        "4"
        "--vision"
        "--vram-reserve-mib"
        "700"
      ];
      cwd = "/run/llm-server";
      # Without a log file the engine's and image encoder's stderr is dropped.
      log = "/var/log/llm-server/strata.log";
      tokenizer = "${pack}/tokenizer";
      model_name = llmModelName;
      lib_dirs = [];
      host = "127.0.0.1";
      port = llmPort;
      backend = "hip";
      open_browser = false;
      # Prompt GEMMs tuned for this GPU and hipBLASLt 1.2.2; the engine falls
      # back to plain hipBLAS for any other hipBLASLt.
      env.STRATA_HIPBLASLT_TUNING = "${strata}/share/strata/tools/hip/${self.lib.artemisDgpuTarget}-hipblaslt-100202.txt";
      # The model card's non-thinking sampling for general tasks.
      sampling = {
        temperature = 0.7;
        top_p = 0.8;
        top_k = 20;
        min_p = 0.0;
        presence_penalty = 1.5;
      };
      vision = {
        exe = "${strata}/bin/strata-vision";
        mmproj = "${strataDir}/${llmMmprojFile}";
        model = shard 1;
        gpu = false;
        max_tokens = 300;
        threads = 4;
      };
    };
    # The server reads its defaults for what a request leaves out from the
    # file beside its config: thinking stays off unless a request asks.
    strataConfigDir = pkgs.linkFarm "llm-server-config" [
      {
        name = "llm-server.json";
        path = pkgs.writeText "llm-server.json" (builtins.toJSON strataConfig);
      }
      {
        name = "llm-server.shared-settings.json";
        path = pkgs.writeText "llm-server.shared-settings.json" (builtins.toJSON {reasoning_effort = "none";});
      }
    ];
  in {
    # The model server and a game both want the whole dGPU.
    gaming.pauseUnits = ["llm-server.service"];

    # The engine keeps its log open in append mode.
    services.logrotate.settings.llm-server = {
      files = "/var/log/llm-server/*.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      copytruncate = true;
      missingok = true;
    };

    users.groups.llm = {};
    users.users.llm = {
      isSystemUser = true;
      group = "llm";
    };

    systemd.services.llm-server-fetch =
      lib.recursiveUpdate
      {
        description = "Fetch the LLM weights and prepare them for Strata";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        # "|" makes the conditions OR: a fetch runs when anything is missing.
        unitConfig.ConditionPathExists =
          map (file: "|!${strataDir}/${file}") (builtins.attrNames llmFiles)
          ++ ["|!${pack}/.done" "|!${mtpRuntime}/.done"];
        serviceConfig = {
          Type = "oneshot";
          User = "llm";
          Group = "llm";
          ExecStart = lib.getExe llmFetch;
          # A ~70 GB download can run well past systemd's 90s start timeout.
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
        description = "Strata (Qwen3.8-Flash-Next IQ2_XS) on ROCm";
        after = ["llm-server-fetch.service" "network-online.target"];
        wants = ["network-online.target"];
        requires = ["llm-server-fetch.service"];
        wantedBy = ["multi-user.target"];
        environment.HIP_VISIBLE_DEVICES = "0";
        serviceConfig = {
          ExecStart = "${lib.getExe strata} --config ${strataConfigDir}/llm-server.json --port ${toString llmPort}";
          User = "llm";
          Group = "llm";
          SupplementaryGroups = ["video" "render"];
          RuntimeDirectory = "llm-server";
          LogsDirectory = "llm-server";
          Restart = "on-failure";
          RestartSec = 5;
          # The pinned experts and KV cache (38 GiB) and up to 8 GiB of parked
          # conversations are anonymous memory; the rest is file cache.
          MemoryMax = "56G";
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
