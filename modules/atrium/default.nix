{
  self,
  config,
  ...
}: let
  actualPort = config.legion.services.actual-budget.ports.app;
  icloudAppleId = "aidan@aidanpinard.co";
  stateDirName = "atrium";
  stateDir = "/var/lib/${stateDirName}";
  codemodeDirName = "atrium-codemode";
  atriumId = 880;
  cacheDir = "${stateDir}/cache";
  modelsDir = "${cacheDir}/models";
  chatPort = 8187;
  embedPort = 8188;
  webPort = 8480;
  webLocalPort = webPort + 1;
  atriumHostname = "atrium.jeiang.dev";
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
  flake.lib = {
    atriumWebPort = webPort;
    atriumWebLocalPort = webLocalPort;
    inherit atriumHostname;
  };

  perSystem = {pkgs, ...}: let
    py = pkgs.python314Packages;
    npmTarball = name: version: hash:
      pkgs.fetchurl {
        url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
        inherit hash;
      };
    basecoat = npmTarball "basecoat-css" "1.0.2" "sha512-C6I5rr7HziIAoBYNGPO5U6HaU/6FuF3iVp++IgoEqqJ836is3XoRty6l1ibXqxnoIRZNnOAYDMX8QxVC+58zhw==";
    htmx = npmTarball "htmx.org" "2.0.11" "sha512-Thx/WtpeOQqSrqBCw/A1cwGJGg4UrVa3+sW0GmrM3p4gJgO89ecH4qtbnyzDDWFvBTqjnIMCgELTNt636dtamA==";
  in {
    packages = {
      atrium = py.buildPythonApplication {
        pname = "atrium";
        version = (builtins.fromTOML (builtins.readFile ./app/pyproject.toml)).project.version;
        src = ./app;
        pyproject = true;
        build-system = [py.setuptools];
        dependencies = [py.anthropic py.caldav py.fastapi py.google-api-python-client py.google-auth py.httpx py.icalendar py.jinja2 py.markdown-it-py py.nh3 py.pydantic-monty py.python-multipart py.sqlite-vec py.trafilatura py.uvicorn py.vobject];
        nativeCheckInputs = [py.respx py.pytestCheckHook];
        meta.mainProgram = "atrium";
      };

      actual-bridge = pkgs.buildNpmPackage {
        pname = "atrium-actual-bridge";
        version = "1.0.0";
        src = ./actual-bridge;
        npmDepsHash = "sha256-kH8TiCSnAt8WqO6hlVXlwesTJZfNVsH86SJxZp3kO3Y=";
        dontNpmBuild = true;
        nativeBuildInputs = [pkgs.makeWrapper];
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/actual-bridge $out/bin
          cp -r bridge.mjs package.json node_modules $out/lib/actual-bridge/
          makeWrapper ${pkgs.nodejs}/bin/node $out/bin/actual-bridge --add-flags $out/lib/actual-bridge/bridge.mjs
          runHook postInstall
        '';
        meta.mainProgram = "actual-bridge";
      };

      atrium-static = pkgs.stdenvNoCC.mkDerivation {
        name = "atrium-static";
        src = ./app/src/atrium/web;
        nativeBuildInputs = [pkgs.tailwindcss_4];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          mkdir -p node_modules/basecoat-css
          tar -xzf ${basecoat} --strip-components=1 -C node_modules/basecoat-css
          tailwindcss --input static/input.css --output app.css --minify
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -Dm444 app.css $out/app.css
          install -Dm444 static/app.js $out/app.js
          install -Dm444 node_modules/basecoat-css/dist/js/all.min.js $out/basecoat/all.min.js
          tar -xzOf ${htmx} package/dist/htmx.min.js > $out/htmx.min.js
          runHook postInstall
        '';
      };
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
    vdirsyncerDir = "${stateDir}/vdirsyncer";
    calendarDir = "${vdirsyncerDir}/calendars";
    contactsDir = "${vdirsyncerDir}/contacts";
    vdirsyncerStatusDir = "${vdirsyncerDir}/status";

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
    atriumStatic = selfpkgs.atrium-static;

    appEnvironment = {
      ATRIUM_DB = "${stateDir}/atrium.db";
      ATRIUM_CACHE_DIR = "${cacheDir}/messages";
      ATRIUM_MODE = "live";
      ATRIUM_CHAT_URL = "http://127.0.0.1:${toString chatPort}/v1";
      ATRIUM_EMBED_URL = "http://127.0.0.1:${toString embedPort}/v1";
      ATRIUM_CONTACTS_DIR = contactsDir;
      ATRIUM_CALENDAR_DIR = calendarDir;
      ATRIUM_TZ = self.lib.facts.timeZone;
      GRAFANA_URL = self.lib.grafanaMeshUrl;
      NTFY_URL = self.lib.ntfyBaseUrl;
      ATRIUM_CODEMODE_SOCKET = "/run/${codemodeDirName}/codemode.sock";
      ICLOUD_APPLE_ID = icloudAppleId;
      ATRIUM_ACTUAL_BRIDGE = lib.getExe selfpkgs.actual-bridge;
      ATRIUM_ACTUAL_DATA = "${cacheDir}/actual";
      ACTUAL_SERVER_URL = "http://${self.lib.netbirdPeers.peria}:${toString actualPort}";
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
          --property=StateDirectory=${stateDirName} --property=StateDirectoryMode=0750 --property=UMask=0027 \
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
      UMask = "0027";
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
      restartUnits = ["atrium-agent-scheduler.service" "atrium-notion-sync.service" "atrium-vdirsyncer-sync.service" "atrium-watch.service" "atrium-web.service" "atrium-web-local.service"];
    };

    networking.nftables.tables.atrium-web = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter - 1; policy accept;
          iifname "${config.services.netbird.clients.default.interface}" tcp dport ${toString webPort} ip saddr != ${self.lib.netbirdPeers.alda} drop
          iifname "${config.services.netbird.clients.default.interface}" tcp dport ${toString webPort} meta nfproto ipv6 drop
        }
      '';
    };

    systemd = {
      # Code-mode worker: one sandboxed instance per connection (the Monty interpreter is not an OS boundary).
      sockets.atrium-codemode = {
        description = "atrium code-mode worker socket";
        wantedBy = ["sockets.target"];
        socketConfig = {
          ListenStream = "/run/${codemodeDirName}/codemode.sock";
          SocketUser = "atrium";
          SocketGroup = "atrium";
          SocketMode = "0600";
          DirectoryMode = "0755";
          Accept = true;
        };
      };

      services = {
        "atrium-codemode@" = {
          description = "atrium code-mode worker";
          serviceConfig = {
            ExecStart = "${lib.getExe atrium} codemode-worker";
            StandardInput = "socket";
            StandardOutput = "socket";
            StandardError = "journal";
            DynamicUser = true;
            PrivateNetwork = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            RestrictAddressFamilies = "AF_UNIX";
            RestrictSUIDSGID = true;
            LockPersonality = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectKernelTunables = true;
            ProtectClock = true;
            MemoryMax = "256M";
            CPUQuota = "50%";
            RuntimeMaxSec = 60;
          };
        };

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

        atrium-agent-scheduler = appService {
          description = "Run atrium's scheduled and nightly agent jobs";
          serviceConfig = {
            ExecStart = "${lib.getExe atrium} agent scheduler";
            Restart = "always";
            RestartSec = 10;
          };
          wantedBy = ["multi-user.target"];
        };

        atrium-web = {
          description = "atrium web UI";
          after = ["network-online.target"] ++ llamaUnits;
          wants = ["network-online.target"] ++ llamaUnits;
          environment =
            appEnvironment
            // {
              ATRIUM_STATIC_DIR = atriumStatic;
              ATRIUM_PUBLIC_HOST = atriumHostname;
            };
          serviceConfig =
            hardening
            // {
              # 0.0.0.0 on purpose: the nftables table above limits 8480 to alda, and binding to the
              # NetBird address would race the interface coming up. Guard rejects any other Host.
              ExecStart = "${lib.getExe atrium} serve --host 0.0.0.0 --port ${toString webPort} --auth proxy --allowed-host ${atriumHostname}";
              Restart = "always";
              RestartSec = 5;
            };
          wantedBy = ["multi-user.target"];
        };

        atrium-web-local = {
          description = "atrium web UI (loopback, no proxy auth)";
          after = ["network-online.target"] ++ llamaUnits;
          wants = ["network-online.target"] ++ llamaUnits;
          environment = appEnvironment // {ATRIUM_STATIC_DIR = atriumStatic;};
          serviceConfig =
            hardening
            // {
              ExecStart = "${lib.getExe atrium} serve --host 127.0.0.1 --port ${toString webLocalPort} --auth local";
              Restart = "always";
              RestartSec = 5;
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

        atrium-notion-sync = appService {
          description = "Mirror Notion into the atrium index";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe atrium} notion sync";
          };
        };

        atrium-scan = appService {
          description = "Scan the mailboxes for rebalance, deletion and label proposals";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe atrium} proposals scan-all";
            TimeoutStartSec = "2h";
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
        atrium-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "2m";
            OnUnitActiveSec = "15m";
          };
        };

        atrium-notion-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "3m";
            OnUnitActiveSec = "15m";
          };
        };

        atrium-scan = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "monthly";
            Persistent = true;
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
