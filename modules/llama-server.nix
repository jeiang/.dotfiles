{self, ...}: {
  flake.lib.llamaServer = {
    lib,
    pkgs,
    name,
    user,
    stateDirName,
    modelsDir,
    models,
  }: let
    llama = self.packages.${pkgs.stdenv.hostPlatform.system}.llama-cpp-atrium;
    fetchUnit = "${name}-models-fetch.service";

    modelsFetch = pkgs.writeShellApplication {
      name = "${name}-models-fetch";
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
        (lib.attrValues models);
    };
  in {
    fetch = {
      description = "Fetch the ${name} model weights";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      unitConfig.ConditionPathExists = map (model: "|!${modelsDir}/${model.file}") (lib.attrValues models);
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = user;
        StateDirectory = stateDirName;
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

    service = unit: {
      description,
      model,
      port,
      host ? "127.0.0.1",
      args,
    }: {
      inherit description;
      after = [fetchUnit];
      requires = [fetchUnit];
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
          ++ args);
        User = user;
        Group = user;
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
  };
}
