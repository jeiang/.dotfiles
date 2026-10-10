{self, ...}: let
  icloudAppleId = "aidan@aidanpinard.co";
  stateDirName = "atrium";
  stateDir = "/var/lib/${stateDirName}";
  atriumId = 880;
  cacheDir = "${stateDir}/cache";
  modelsDir = "${cacheDir}/models";
  chatPort = 8187;
  embedPort = 8188;
  hf = repo: rev: file: "https://huggingface.co/${repo}/resolve/${rev}/${file}";
  models = {
    chat = {
      file = "Qwen3.5-9B-Q4_K_M.gguf";
      url = hf "lmstudio-community/Qwen3.5-9B-GGUF" "1379f25c6b505a3fc737bd7818cb09389cf807c1" "Qwen3.5-9B-Q4_K_M.gguf";
      sha256 = "cd76ec205963b3b33350093e6904d9de16c4e666fd104e1f632d25c7f15f2a13";
    };
    embed = {
      file = "embeddinggemma-2-Q8_0.gguf";
      url = hf "ggml-org/embeddinggemma-2-GGUF" "bfcd298762cc34d0357ece5ebdd31791a3a374d8" "embeddinggemma-2-Q8_0.gguf";
      sha256 = "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135";
    };
  };
  llamaUnits = ["atrium-llm.service" "atrium-embed.service"];
in {
  perSystem = {pkgs, ...}: {
    packages.atrium = pkgs.python314Packages.buildPythonApplication {
      pname = "atrium";
      version = (builtins.fromTOML (builtins.readFile ./app/pyproject.toml)).project.version;
      src = ./app;
      pyproject = true;
      build-system = [pkgs.python314Packages.setuptools];
      dependencies = [pkgs.python314Packages.sqlite-vec];
      nativeCheckInputs = [pkgs.python314Packages.pytestCheckHook];
      meta.mainProgram = "atrium";
    };
  };

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    llama = selfpkgs.llama-cpp-atrium;
    envFile = config.sops.secrets."atrium/env".path;
    xdgConfigHome = "${stateDir}/config";
    himalayaConfig = "${xdgConfigHome}/himalaya/config.toml";
    vdirsyncerDir = "${stateDir}/vdirsyncer";
    calendarDir = "${vdirsyncerDir}/calendars";
    contactsDir = "${vdirsyncerDir}/contacts";
    vdirsyncerStatusDir = "${vdirsyncerDir}/status";

    mailTriage = pkgs.writers.writePython3Bin "atrium-mail-triage" {flakeIgnore = ["E501"];} (builtins.readFile ./mail_triage.py);

    himalayaTemplate = pkgs.writeText "atrium-himalaya-config" ''
      [accounts.icloud]
      default = true
      email = "${icloudAppleId}"
      display-name = "Aidan Pinard"

      [accounts.icloud.imap]
      server = "imap.mail.me.com:993"
      tls = {}

      [accounts.icloud.imap.sasl.plain]
      username = "''${ICLOUD_MAIL_USERNAME}"
      password.cmd = "printenv ICLOUD_APP_PASSWORD"
    '';

    renderHimalayaConfig = pkgs.writeShellScript "atrium-render-himalaya-config" ''
      set -euo pipefail
      install -d -m 0700 ${builtins.dirOf himalayaConfig}
      ${pkgs.gettext}/bin/envsubst '$ICLOUD_MAIL_USERNAME' < ${himalayaTemplate} > ${himalayaConfig}
      chmod 0600 ${himalayaConfig}
    '';

    vdirsyncerConfig = pkgs.writeText "atrium-vdirsyncer-config" ''
      [general]
      status_path = "${vdirsyncerStatusDir}"

      [pair icloud_calendar]
      a = "icloud_calendar_local"
      b = "icloud_calendar_remote"
      collections = ["from b"]

      [storage icloud_calendar_local]
      type = "filesystem"
      path = "${calendarDir}"
      fileext = ".ics"

      [storage icloud_calendar_remote]
      type = "caldav"
      url = "https://caldav.icloud.com/"
      username = "${icloudAppleId}"
      password.fetch = ["command", "printenv", "ICLOUD_APP_PASSWORD"]
      item_types = ["VEVENT"]

      [pair icloud_contacts]
      a = "icloud_contacts_local"
      b = "icloud_contacts_remote"
      collections = ["from b"]

      [storage icloud_contacts_local]
      type = "filesystem"
      path = "${contactsDir}"
      fileext = ".vcf"

      [storage icloud_contacts_remote]
      type = "carddav"
      url = "https://contacts.icloud.com/"
      username = "${icloudAppleId}"
      password.fetch = ["command", "printenv", "ICLOUD_APP_PASSWORD"]
      read_only = true
    '';

    inherit (selfpkgs) atrium;

    appEnvironment = {
      ATRIUM_DB = "${stateDir}/atrium.db";
      ATRIUM_CACHE_DIR = "${cacheDir}/messages";
      ATRIUM_MODE = "shadow";
      ATRIUM_CHAT_URL = "http://127.0.0.1:${toString chatPort}/v1";
      ATRIUM_EMBED_URL = "http://127.0.0.1:${toString embedPort}/v1";
      ATRIUM_CONTACTS_DIR = contactsDir;
      ATRIUM_JEV_DB = "${stateDir}/jev-mail.db";
    };

    modelsFetch = pkgs.writeShellApplication {
      name = "atrium-models-fetch";
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

    atriumRun = pkgs.writeShellApplication {
      name = "atrium-run";
      runtimeInputs = [pkgs.systemd];
      text = ''
        exec systemd-run --pipe --wait --collect --quiet \
          --property=User=atrium --property=Group=atrium \
          --property=StateDirectory=${stateDirName} \
          --property=EnvironmentFile=${envFile} \
          ${lib.concatStringsSep " \\\n          " (lib.mapAttrsToList (name: value: "--setenv=${name}=${value}") appEnvironment)} \
          -- ${lib.getExe atrium} "$@"
      '';
    };

    llamaService = name: {
      description,
      model,
      port,
      args,
    }: {
      inherit description;
      after = ["atrium-models-fetch.service"];
      requires = ["atrium-models-fetch.service"];
      wantedBy = ["multi-user.target"];
      environment.XDG_CACHE_HOME = "/var/cache/${name}";
      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([
            "${llama}/bin/llama-server"
            "--model"
            "${modelsDir}/${model.file}"
            "--host"
            "127.0.0.1"
            "--port"
            (toString port)
            "--n-gpu-layers"
            "99"
            "--parallel"
            "1"
          ]
          ++ args);
        User = "atrium";
        Group = "atrium";
        SupplementaryGroups = ["video" "render"];
        CacheDirectory = name;
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

    appService = args:
      lib.recursiveUpdate
      {
        after = ["network-online.target"] ++ llamaUnits;
        wants = ["network-online.target"] ++ llamaUnits;
        environment = appEnvironment;
        serviceConfig = hardening;
      }
      args;

    hardening = {
      User = "atrium";
      Group = "atrium";
      StateDirectory = stateDirName;
      StateDirectoryMode = "0750";
      EnvironmentFile = envFile;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
    };
  in {
    users.users.atrium = {
      isSystemUser = true;
      uid = atriumId;
      group = "atrium";
    };
    users.groups.atrium.gid = atriumId;

    gaming.pauseUnits = llamaUnits;

    environment.systemPackages = [atriumRun];

    systemd.tmpfiles.rules = ["d ${cacheDir} 0750 atrium atrium -"];

    persistence.directories = [
      {
        directory = stateDir;
        user = "atrium";
        group = "atrium";
        mode = "0750";
      }
    ];

    sops.secrets."atrium/env" = {
      sopsFile = ./secrets.yaml;
      mode = "0400";
      restartUnits = ["atrium-mail-triage.service" "atrium-vdirsyncer-sync.service" "atrium-watch.service"];
    };

    systemd = {
      services = {
        atrium-models-fetch = {
          description = "Fetch the atrium model weights";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          unitConfig.ConditionPathExists = map (model: "|!${modelsDir}/${model.file}") (lib.attrValues models);
          serviceConfig = {
            Type = "oneshot";
            User = "atrium";
            Group = "atrium";
            StateDirectory = stateDirName;
            ExecStart = lib.getExe modelsFetch;
            TimeoutStartSec = 0;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
          };
        };

        atrium-llm = llamaService "atrium-llm" {
          description = "Qwen3.5-9B chat server for atrium";
          model = models.chat;
          port = chatPort;
          args = [
            "--ctx-size"
            "8192"
            "--jinja"
            "--chat-template-kwargs"
            (builtins.toJSON {enable_thinking = false;})
          ];
        };

        atrium-embed = llamaService "atrium-embed" {
          description = "EmbeddingGemma 2 embedding server for atrium";
          model = models.embed;
          port = embedPort;
          args = [
            "--embedding"
            "--ctx-size"
            "2048"
            "--batch-size"
            "2048"
            "--ubatch-size"
            "2048"
          ];
        };

        atrium-watch = appService {
          description = "Watch the atrium mailboxes for new mail";
          serviceConfig = {
            ExecStart = "${lib.getExe atrium} watch";
            Restart = "always";
            RestartSec = 10;
          };
          wantedBy = ["multi-user.target"];
        };

        atrium-sync = appService {
          description = "Reconcile the atrium mail index";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe atrium} sync";
          };
        };

        atrium-mail-triage = {
          description = "Triage unseen iCloud mail with Jev";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.himalaya];
          environment.XDG_CONFIG_HOME = xdgConfigHome;
          serviceConfig =
            hardening
            // {
              Type = "oneshot";
              ExecStartPre = renderHimalayaConfig;
              ExecStart = lib.getExe mailTriage;
            };
        };

        atrium-vdirsyncer-sync = {
          description = "Sync iCloud calendar and contacts via vdirsyncer";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.vdirsyncer];
          environment.VDIRSYNCER_CONFIG = vdirsyncerConfig;
          serviceConfig =
            hardening
            // {
              Type = "oneshot";
            };
          script = ''
            set -euo pipefail

            install -d -m 0700 "${calendarDir}" "${contactsDir}" "${vdirsyncerStatusDir}"

            # discover prompts on stdin for each new remote collection and has
            # no --yes flag; a bounded y-feed (not `yes |`, which would
            # SIGPIPE under pipefail) keeps it non-interactive.
            printf 'y\n%.0s' $(seq 1 100) | vdirsyncer discover
            vdirsyncer sync
          '';
        };
      };

      timers = {
        atrium-mail-triage = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "*:0/15";
            Persistent = true;
          };
        };

        atrium-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "2m";
            OnUnitActiveSec = "15m";
          };
        };

        atrium-vdirsyncer-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "1m";
            OnUnitActiveSec = "15m";
          };
        };
      };
    };
  };
}
