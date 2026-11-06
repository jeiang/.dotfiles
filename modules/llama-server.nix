{self, ...}: let
  embeddinggemma = self.lib.huggingface "ggml-org/embeddinggemma-2-GGUF" "bfcd298762cc34d0357ece5ebdd31791a3a374d8";
  qwen = self.lib.huggingface "lmstudio-community/Qwen3.5-9B-GGUF" "1379f25c6b505a3fc737bd7818cb09389cf807c1";
in {
  flake.lib = {
    huggingface = repo: rev: path: sha256: {
      file = baseNameOf path;
      url = "https://huggingface.co/${repo}/resolve/${rev}/${path}";
      inherit sha256;
    };

    llamaModels = {
      embeddinggemma = embeddinggemma "embeddinggemma-2-Q8_0.gguf" "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135";
      embeddinggemmaProjector = embeddinggemma "mmproj-embeddinggemma-2-Q8_0.gguf" "c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f";
      qwen35 = qwen "Qwen3.5-9B-Q4_K_M.gguf" "cd76ec205963b3b33350093e6904d9de16c4e666fd104e1f632d25c7f15f2a13";
      qwen35Projector = qwen "mmproj-Qwen3.5-9B-BF16.gguf" "330d17547bfdbcd0e7a0cb3f4b06b4ceeac0aaa1e449122d9d66ef957aeb74b3";
    };

    # A set of llama-server units `<name>-<server>`, plus the `<name>-models-fetch`
    # unit they require, all running as the system user `name` with weights under
    # /var/lib/<name>. Each server is {description, model, projector?, port, host?, args}.
    llamaServer = {
      lib,
      pkgs,
      name,
      modelsDir,
      servers,
    }: let
      llama = self.packages.${pkgs.stdenv.hostPlatform.system}.llama-cpp-atrium;
      fetchName = "${name}-models-fetch";
      models = lib.concatMap (server: [server.model] ++ lib.optional (server ? projector) server.projector) (lib.attrValues servers);

      modelsFetch = pkgs.writeShellApplication {
        name = fetchName;
        runtimeInputs = [pkgs.curl pkgs.coreutils];
        text =
          ''
            mkdir -p "${modelsDir}"
          ''
          + lib.concatMapStrings (model: ''
            if [ ! -e "${modelsDir}/${model.file}" ]; then
              tmp="${modelsDir}/.${model.file}.part"
              curl --fail --location --retry 3 --retry-delay 5 --continue-at - -o "$tmp" "${model.url}"
              if ! printf '%s  %s\n' "${model.sha256}" "$tmp" | sha256sum --check --status; then
                rm -f "$tmp"
                exit 1
              fi
              mv "$tmp" "${modelsDir}/${model.file}"
            fi
          '')
          models;
      };

      service = unit: {
        description,
        model,
        projector ? null,
        port,
        host ? "127.0.0.1",
        args,
      }: {
        inherit description;
        after = ["${fetchName}.service"];
        requires = ["${fetchName}.service"];
        wantedBy = ["multi-user.target"];
        environment.XDG_CACHE_HOME = "/var/cache/${unit}";
        serviceConfig = {
          ExecStart = lib.escapeShellArgs ([
              "${llama}/bin/llama-server"
              "--model"
              "${modelsDir}/${model.file}"
              "--host"
              host
              "--port"
              (toString port)
              "--n-gpu-layers"
              "99"
              "--parallel"
              "1"
            ]
            ++ lib.optionals (projector != null) ["--mmproj" "${modelsDir}/${projector.file}"]
            ++ args);
          User = name;
          Group = name;
          SupplementaryGroups = ["video" "render"];
          CacheDirectory = unit;
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = [modelsDir];
          PrivateTmp = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    in {
      units = map (server: "${name}-${server}.service") (lib.attrNames servers);
      services =
        {
          ${fetchName} = {
            description = "Fetch the ${name} model weights";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            unitConfig.ConditionPathExists = map (model: "|!${modelsDir}/${model.file}") models;
            serviceConfig = {
              Type = "oneshot";
              User = name;
              Group = name;
              StateDirectory = name;
              StateDirectoryMode = "0750";
              UMask = "0027";
              ExecStart = lib.getExe modelsFetch;
              TimeoutStartSec = 0;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              NoNewPrivileges = true;
            };
          };
        }
        // lib.mapAttrs' (server: spec: let
          unit = "${name}-${server}";
        in
          lib.nameValuePair unit (service unit spec))
        servers;
    };
  };
}
