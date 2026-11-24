{self, ...}: let
  port = 8095;
  stateDir = "/var/lib/strata";
  hf = self.lib.huggingface "strata-engine/Inkling-2-Mini-Strata" "04996a1e2c45009b6a04f2af126cb6bdb2ba3587";
  pack = hf "Inkling-2-Mini-SQ-15.strata" "2ea32eed533afba257e2cbee7b073dc2c3da80fe55d1d2d794779b5498e30737";
  tokenizerJson = hf "tokenizer.json" "7f332727f9a3f093dd452a39cc978e6757627e5dad1b0673aa4e75174f236dd6";
  modelName = "inkling-2-mini";
  maxContext = 131072;
in {
  flake.lib = {
    strataPort = port;
    strataModelName = modelName;
    strataMaxContext = maxContext;
  };

  nixos.modules.workstation = {
    lib,
    pkgs,
    ...
  }: let
    strata = self.packages.${pkgs.stdenv.hostPlatform.system}.strata;
    weights = "${stateDir}/weights";
    tokenizer = "${stateDir}/tokenizer";

    fetch = pkgs.writeShellApplication {
      name = "strata-fetch";
      runtimeInputs = [pkgs.curl pkgs.coreutils strata];
      text =
        ''
          mkdir -p "${weights}"
        ''
        + lib.concatMapStrings (self.lib.fetchWeights weights) [pack tokenizerJson]
        + ''
          if [ ! -e "${tokenizer}/vocab.json" ]; then
            rm -rf "${tokenizer}" "${tokenizer}.part"
            strata-inkling-tokenizer --strata "${weights}/${pack.file}" --hf-json "${weights}/${tokenizerJson.file}" --out "${tokenizer}.part"
            mv "${tokenizer}.part" "${tokenizer}"
          fi
        '';
    };

    config = pkgs.writeText "strata.json" (builtins.toJSON {
      exe = "${strata.engine}/libexec/strata/strata-inkling";
      # Leaves room for atrium's embedding server, which otherwise falls back to system memory when it restarts.
      args = ["--native" "${weights}/${pack.file}" "--max-context" (toString maxContext) "--vram-reserve-mib" "512"];
      cwd = "/run/strata";
      inherit tokenizer;
      model_name = modelName;
      host = "127.0.0.1";
      inherit port;
      backend = "hip";
      # Without a log file the engine's stderr is dropped.
      log = "/var/log/strata/engine.log";
      open_browser = false;
    });
  in {
    users.groups.strata = {};
    users.users.strata = {
      isSystemUser = true;
      group = "strata";
    };

    persistence.directories = [
      {
        directory = stateDir;
        user = "strata";
        group = "strata";
        mode = "0750";
      }
    ];

    # The model server and a game both want the whole dGPU.
    gaming.pauseUnits = ["strata.service"];
    monitoredUnits = ["strata.service"];

    # The engine keeps its log open in append mode.
    services.logrotate.settings.strata = {
      files = "/var/log/strata/*.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      copytruncate = true;
      missingok = true;
    };

    systemd.services = {
      strata-fetch = {
        description = "Fetch the Inkling 2 Mini weights for Strata";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        unitConfig.ConditionPathExists = ["|!${weights}/${pack.file}" "|!${weights}/${tokenizerJson.file}" "|!${tokenizer}/vocab.json"];
        serviceConfig = {
          Type = "oneshot";
          User = "strata";
          Group = "strata";
          UMask = "0027";
          ExecStart = lib.getExe fetch;
          TimeoutStartSec = 0;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [stateDir];
          NoNewPrivileges = true;
        };
      };

      strata = {
        description = "Strata serving Inkling 2 Mini";
        after = ["strata-fetch.service"];
        requires = ["strata-fetch.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${lib.getExe strata} --config ${config} --port ${toString port}";
          User = "strata";
          Group = "strata";
          SupplementaryGroups = ["video" "render"];
          RuntimeDirectory = "strata";
          LogsDirectory = "strata";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = [stateDir];
          PrivateTmp = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    };
  };
}
