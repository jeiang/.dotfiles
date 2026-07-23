{
  inputs,
  lib,
  ...
}: {
  flake.nixosModules.hermes = {
    config,
    pkgs,
    ...
  }: let
    inherit (config.hermes) stateDir workspace;
    memoryCheckout = "${workspace}/knowledge-base-memory";
    memoryDirectory = "${memoryCheckout}/memories/hermes";
    commandTools = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.devenv
      pkgs.fd
      pkgs.findutils
      pkgs.gawk
      pkgs.git
      pkgs.gnused
      pkgs.jq
      pkgs.just
      pkgs.nix
      pkgs.openssh
      pkgs.ripgrep
    ];
    codexConfig = pkgs.writeText "hermes-codex-config.toml" ''
      default_permissions = "hermes"
      approval_policy = "never"
      web_search = "live"
      model = "gpt-5.6-terra"
      model_reasoning_effort = "medium"

      [permissions.hermes]
      extends = ":workspace"

      [permissions.hermes.workspace_roots]
      "${workspace}" = true

      [permissions.hermes.filesystem]
      ":root" = "read"
      "/tmp" = "write"
      "${workspace}" = "write"
      "${stateDir}/.hermes/memories" = "write"
      "${stateDir}/requests" = "write"
      "${stateDir}/approval-status" = "read"
      "${stateDir}/reports" = "read"
      "${stateDir}/.hermes/.env" = "deny"
      "${stateDir}/.hermes/auth.json" = "deny"
      "${stateDir}/codex/auth.json" = "deny"
      # systemd InaccessiblePaths already masks host credentials and broker
      # state before Codex constructs its nested bubblewrap namespace.
      "/nix/var/nix/daemon-socket/socket" = "deny"

      [permissions.hermes.filesystem.":workspace_roots"]
      "." = "write"
      ".git" = "write"
      ".agents" = "read"
      ".codex" = "read"
      "AGENTS.md" = "read"

      [permissions.hermes.network]
      enabled = true
      mode = "limited"
      allow_local_binding = false

      [permissions.hermes.network.domains]
      "*" = "allow"
    '';
    publicationSourcesFile =
      pkgs.writeText "hermes-publication-sources.json"
      (builtins.toJSON config.hermes.publicationSources);
    approvalBroker = pkgs.writeShellApplication {
      name = "hermes-approval-broker";
      runtimeInputs = [pkgs.gh pkgs.git pkgs.python3];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-approval.py} broker "$@"
      '';
    };
    approvalDispatcher = pkgs.writeShellApplication {
      name = "hermes-approval-dispatcher";
      runtimeInputs = [pkgs.python3 pkgs.systemd];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-approval.py} dispatch "$@"
      '';
    };
    commandRunner = pkgs.writeShellApplication {
      name = "hermes-command-runner";
      runtimeInputs = [pkgs.python3] ++ commandTools;
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-approval.py} run "$@"
      '';
    };
    requestHelper = pkgs.writeShellApplication {
      name = "hermes-request";
      runtimeInputs = [pkgs.python3];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-approval.py} request "$@"
      '';
    };
    memoryBatch = pkgs.writeShellApplication {
      name = "hermes-memory-batch";
      runtimeInputs = [pkgs.git pkgs.python3 requestHelper];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-approval.py} memory-batch
      '';
    };
    aggregateSnapshot = pkgs.writers.writePython3Bin "hermes-snapshot-aggregate" {flakeIgnore = ["E501"];} (builtins.readFile ./hermes-snapshot-aggregate.py);
    workspaceInstructions = pkgs.writeText "hermes-workspace-AGENTS.md" ''
      # Hermes workspace policy

      - Work freely inside `${workspace}`, including Git metadata.
      - Do not attempt to read credentials, broker state, approval queues, or the Nix daemon socket.
      - Use `hermes-request command` for a command blocked by the normal permission profile.
      - Use `hermes-request service` for an allowed Hermes service lifecycle action.
      - Use `hermes-request publication` to publish an exact `codex/` branch commit. Hermes has no direct GitHub write credential.
      - General knowledge may be written only when the user explicitly requests or directs it.
      - Store native memory only in `knowledge-base-memory/memories/hermes`.
      - Organize directed general knowledge by subject. Put structural reorganizations in a dedicated branch and validate internal Markdown links.
    '';
    hermesSettings = {
      model = {
        provider = "openai-codex";
        default = "gpt-5.6-terra";
        openai_runtime = "codex_app_server";
      };
      fallback_providers = [];
      timezone = "America/Port_of_Spain";
      streaming = {
        enabled = true;
        transport = "auto";
      };
      agent.reasoning_effort = "medium";
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        write_approval = false;
      };
      skills.write_approval = true;
      unauthorized_dm_behavior = "ignore";
      gateway.platforms.telegram.extra = {
        allowed_chats = ["__hermes_dm_only__"];
        group_allowed_chats = [];
        guest_mode = false;
        observe_unmentioned_group_messages = false;
      };
    };
    hermesConfig = pkgs.writeText "hermes-config.yaml" (builtins.toJSON hermesSettings);
    uniqueRepositories =
      lib.unique
      (lib.mapAttrsToList (_: source: source.repository) config.hermes.publicationSources);
    mirrorPath = repo: "${stateDir}/mirrors/${builtins.replaceStrings ["/"] ["__"] repo}.git";
    hermesGitconfig = pkgs.writeText "hermes-gitconfig" ''
      [user]
        name = Hermes Agent
        email = 31970261+jeiang@users.noreply.github.com
      [safe]
        directory = *
      ${lib.concatMapStringsSep "\n" (repo: "\tdirectory = ${mirrorPath repo}") uniqueRepositories}
    '';
    stateInit = pkgs.writeShellApplication {
      name = "hermes-state-init";
      runtimeInputs = [pkgs.acl pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.jq];
      text = ''
        install -d -o hermes -g hermes -m 0751 ${stateDir}
        install -d -o hermes -g hermes -m 2770 ${stateDir}/.hermes
        for sub in cron sessions logs memories plugins; do
          install -d -o hermes -g hermes -m 2770 "${stateDir}/.hermes/$sub"
        done
        install -d -o hermes -g hermes -m 0750 ${stateDir}/home
        install -o hermes -g hermes -m 0640 ${hermesConfig} ${stateDir}/.hermes/config.yaml
        install -o hermes -g hermes -m 0640 ${config.sops.secrets."hermes/env".path} ${stateDir}/.hermes/.env
        install -o hermes -g hermes-workspace -m 0644 ${hermesGitconfig} ${stateDir}/.gitconfig

        if ! jq -e '(.providers["openai-codex"].tokens.access_token // "") | length > 0' \
            ${stateDir}/.hermes/auth.json >/dev/null 2>&1; then
          umask 077
          jq -n --slurpfile c ${config.sops.secrets."hermes/codex-auth.json".path} \
            '{providers: {"openai-codex": {tokens: $c[0].tokens, last_refresh: (now | todateiso8601), auth_mode: "chatgpt"}}}' \
            > ${stateDir}/.hermes/auth.json
          chown hermes:hermes ${stateDir}/.hermes/auth.json
          chmod 0600 ${stateDir}/.hermes/auth.json
        fi

        install -d -o hermes -g hermes -m 0700 ${stateDir}/codex
        install -d -o hermes-approval-broker -g hermes-approval-broker -m 0750 ${stateDir}/publisher
        install -d -o hermes-approval-broker -g hermes-approval-broker -m 0700 ${stateDir}/publisher/home
        install -d -o hermes-approval-broker -g hermes-approval-broker -m 0700 ${stateDir}/publisher/gh
        for sub in announced completed rejected dispatch; do
          install -d -o hermes-approval-broker -g hermes-approval-broker -m 0750 "${stateDir}/publisher/$sub"
        done
        chown -R hermes-approval-broker:hermes-approval-broker ${stateDir}/publisher

        install -d -o hermes-approval-broker -g hermes-publish -m 0750 ${stateDir}/mirrors
        chown -R hermes-approval-broker:hermes-publish ${stateDir}/mirrors
        install -d -o hermes-approval-broker -g hermes-requests -m 2730 ${stateDir}/requests
        install -d -o hermes-approval-broker -g hermes-results -m 2770 ${stateDir}/approval-status
        install -d -o root -g hermes-command -m 0750 ${stateDir}/commands
        for sub in jobs cancel inflight processed; do
          install -d -o root -g hermes-command -m 0750 "${stateDir}/commands/$sub"
        done
        install -d -o hermes-command -g hermes-results -m 2770 ${stateDir}/command-results
        install -d -o hermes -g hermes -m 0750 ${stateDir}/memory-batch

        install -d -o hermes -g hermes-workspace -m 2770 ${workspace}
        if [ -d ${workspace}/.publisher-requests ] &&
            find ${workspace}/.publisher-requests -mindepth 1 -print -quit | grep -q .; then
          echo "legacy Hermes publication requests must be handled before activation" >&2
          exit 1
        fi
        rmdir ${workspace}/.publisher-requests 2>/dev/null || true
        find -P ${workspace} -type d -exec setfacl \
          -m g:hermes-workspace:rwx,g:hermes-publish:r-x \
          -m d:g:hermes-workspace:rwx,d:g:hermes-publish:r-x,d:m:rwx {} +
        find -P ${workspace} -type f -exec setfacl \
          -m g:hermes-workspace:rw-,g:hermes-publish:r-- {} +
        find -P ${workspace} -type f -perm /111 -exec setfacl \
          -m g:hermes-workspace:rwx,g:hermes-publish:r-x {} +
        rm -f ${workspace}/AGENTS.md
        install -o root -g hermes-workspace -m 0444 ${workspaceInstructions} ${workspace}/AGENTS.md

        install -d -o root -g hermes -m 0750 ${stateDir}/reports
        install -d -o root -g hermes -m 0750 ${stateDir}/reports/history
      '';
    };
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    options.hermes = {
      enable = lib.mkEnableOption "the isolated Hermes Agent deployment";
      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/hermes";
        description = "Persistent Hermes Volume mountpoint.";
      };
      workspace = lib.mkOption {
        type = lib.types.str;
        default = "${config.hermes.stateDir}/worktrees";
        description = "Workspace writable by Hermes and approved command execution.";
      };
      peerAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Private addresses whose observed snapshots are aggregated.";
      };
      metricsUrl = lib.mkOption {
        type = lib.types.str;
        description = "VictoriaMetrics base URL queried by the aggregator.";
      };
      publicationSources = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            repository = lib.mkOption {
              type = lib.types.str;
              description = "GitHub owner/repository allowed for publication.";
            };
            worktree = lib.mkOption {
              type = lib.types.str;
              description = "Fixed Hermes worktree used as the publication source.";
            };
          };
        });
        default = {
          cornn-flaek = {
            repository = "jeiang/.dotfiles";
            worktree = "${config.hermes.workspace}/cornn-flaek";
          };
          knowledge-base = {
            repository = "jeiang/knowledge-base";
            worktree = "${config.hermes.workspace}/knowledge-base";
          };
          knowledge-base-memory = {
            repository = "jeiang/knowledge-base";
            worktree = "${config.hermes.workspace}/knowledge-base-memory";
          };
        };
        description = "Named, fixed worktrees and repositories allowed for publication.";
      };
    };

    config = lib.mkIf config.hermes.enable {
      sops.secrets = {
        "hermes/env" = {
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
        "hermes/codex-auth.json" = {
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
        "hermes/publisher-env" = {
          owner = "hermes-approval-broker";
          group = "hermes-approval-broker";
          mode = "0400";
        };
      };

      services.hermes-agent = {
        enable = true;
        inherit stateDir;
        workingDirectory = workspace;
        environmentFiles = [config.sops.secrets."hermes/env".path];
        extraDependencyGroups = ["messaging"];
        extraPackages = commandTools ++ [pkgs.codex requestHelper];
        settings = hermesSettings;
      };

      systemd = {
        services = {
          hermes-state-init = {
            description = "Create Hermes state directories on the mounted volume";
            wantedBy = ["multi-user.target"];
            before = [
              "hermes-agent.service"
              "hermes-approval-broker.service"
              "hermes-approval-dispatcher.service"
              "hermes-command-runner.service"
              "hermes-memory-batch.service"
              "hermes-snapshot-aggregate.service"
            ];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${stateInit}/bin/hermes-state-init";
            };
          };

          hermes-agent = {
            requires = ["hermes-state-init.service"];
            after = ["hermes-state-init.service"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              ConditionPathIsDirectory = memoryDirectory;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Environment = [
                "CODEX_HOME=${stateDir}/codex"
                "TZ=America/Port_of_Spain"
                "HERMES_APPROVAL_REQUESTS=${stateDir}/requests"
                "HERMES_APPROVAL_STATUS=${stateDir}/approval-status"
                "HERMES_TELEGRAM_DISABLE_FALLBACK_IPS=1"
              ];
              MemoryMax = "1G";
              CPUQuota = "100%";
              ProtectProc = "invisible";
              BindPaths = ["${memoryDirectory}:${stateDir}/.hermes/memories"];
              InaccessiblePaths = [
                "${stateDir}/publisher"
                "${stateDir}/commands"
                "${stateDir}/command-results"
                "/etc/ssh"
                "/home"
                "/root"
                "/run/credentials"
                "/run/secrets"
                "/var/lib/private"
                "-/var/lib/sops-nix"
              ];
              ReadOnlyPaths = [
                "${stateDir}/approval-status"
                "${stateDir}/mirrors"
                "${stateDir}/reports"
                "${workspace}/AGENTS.md"
                "-${workspace}/.agents"
                "-${workspace}/.codex"
              ];
              ExecStartPre = lib.mkAfter [
                "+${pkgs.coreutils}/bin/install -d -o hermes -g hermes -m 0700 ${stateDir}/codex"
                "+${pkgs.bash}/bin/sh -c 'test -s ${stateDir}/codex/auth.json || ${pkgs.coreutils}/bin/install -o hermes -g hermes -m 0600 ${config.sops.secrets."hermes/codex-auth.json".path} ${stateDir}/codex/auth.json'"
                "+${pkgs.coreutils}/bin/install -o hermes -g hermes -m 0640 ${codexConfig} ${stateDir}/codex/config.toml"
              ];
            };
          };

          hermes-approval-broker = {
            description = "Hermes Telegram approval and GitHub publication broker";
            wantedBy = ["multi-user.target"];
            requires = ["hermes-state-init.service"];
            after = ["network-online.target" "hermes-state-init.service"];
            wants = ["network-online.target"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              User = "hermes-approval-broker";
              Group = "hermes-approval-broker";
              Environment = [
                "HOME=${stateDir}/publisher/home"
                "GH_CONFIG_DIR=${stateDir}/publisher/gh"
                "HERMES_APPROVAL_REQUESTS=${stateDir}/requests"
                "HERMES_APPROVAL_STATUS=${stateDir}/approval-status"
                "HERMES_APPROVAL_MIRRORS=${stateDir}/mirrors"
                "HERMES_APPROVAL_SOURCES_FILE=${publicationSourcesFile}"
                "HERMES_APPROVAL_AGENT_USER=hermes"
              ];
              EnvironmentFile = config.sops.secrets."hermes/publisher-env".path;
              ExecStart = "${approvalBroker}/bin/hermes-approval-broker ${stateDir}/publisher";
              Restart = "always";
              RestartSec = "5s";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ProtectProc = "invisible";
              ReadWritePaths = [
                "${stateDir}/publisher"
                "${stateDir}/mirrors"
                "${stateDir}/requests"
                "${stateDir}/approval-status"
              ];
            };
          };

          hermes-approval-dispatcher = {
            description = "Dispatch approved Hermes commands and service actions";
            wantedBy = ["multi-user.target"];
            requires = ["hermes-state-init.service"];
            after = ["hermes-state-init.service"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              User = "root";
              Group = "root";
              Environment = [
                "HERMES_APPROVAL_DISPATCH=${stateDir}/publisher/dispatch"
                "HERMES_APPROVAL_STATUS=${stateDir}/approval-status"
                "HERMES_APPROVAL_SOURCES_FILE=${publicationSourcesFile}"
                "HERMES_APPROVAL_BROKER_USER=hermes-approval-broker"
                "HERMES_COMMAND_GROUP=hermes-command"
              ];
              ExecStart = "${approvalDispatcher}/bin/hermes-approval-dispatcher ${stateDir}/commands";
              Restart = "always";
              RestartSec = "2s";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ProtectProc = "invisible";
              ReadWritePaths = [
                "${stateDir}/publisher/dispatch"
                "${stateDir}/commands"
                "${stateDir}/approval-status"
              ];
            };
          };

          hermes-command-runner = {
            description = "Run one approved Hermes command at a time";
            wantedBy = ["multi-user.target"];
            requires = ["hermes-state-init.service"];
            after = ["network-online.target" "hermes-state-init.service"];
            wants = ["network-online.target"];
            path = commandTools;
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              User = "hermes-command";
              Group = "hermes-command";
              Environment = [
                "HOME=${stateDir}"
                "HERMES_COMMAND_WORKSPACE=${workspace}"
                "HERMES_COMMAND_RESULTS=${stateDir}/command-results"
                "HERMES_APPROVAL_STATUS=${stateDir}/approval-status"
                "HERMES_COMMAND_SHELL=${pkgs.bash}/bin/bash"
                "XDG_CACHE_HOME=/tmp/cache"
                "XDG_CONFIG_HOME=/tmp/config"
              ];
              ExecStart = "${commandRunner}/bin/hermes-command-runner ${stateDir}/commands";
              Restart = "always";
              RestartSec = "2s";
              UMask = "0007";
              MemoryMax = "500M";
              CPUQuota = "100%";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ProtectProc = "invisible";
              RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
              IPAddressDeny = [
                "localhost"
                "link-local"
                "multicast"
                "10.0.0.0/8"
                "100.64.0.0/10"
                "172.16.0.0/12"
                "192.168.0.0/16"
                "fc00::/7"
                "fe80::/10"
              ];
              InaccessiblePaths = [
                "${stateDir}/.hermes"
                "${stateDir}/codex"
                "${stateDir}/publisher"
                "${stateDir}/requests"
                "/etc/ssh"
                "/home"
                "/root"
                "/run/credentials"
                "/run/secrets"
                "/var/lib/private"
                "-/var/lib/sops-nix"
              ];
              ReadWritePaths = [
                workspace
                "${stateDir}/approval-status"
                "${stateDir}/command-results"
              ];
              ReadOnlyPaths = [
                "${workspace}/AGENTS.md"
                "-${workspace}/.agents"
                "-${workspace}/.codex"
              ];
            };
          };

          hermes-memory-batch = {
            description = "Commit Hermes native memory for human review";
            requires = ["hermes-state-init.service"];
            after = ["hermes-state-init.service"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              ConditionPathIsDirectory = memoryDirectory;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Type = "oneshot";
              User = "hermes";
              Group = "hermes";
              Environment = [
                "HOME=${stateDir}"
                "HERMES_MEMORY_CHECKOUT=${memoryCheckout}"
                "HERMES_MEMORY_PENDING_ID=${stateDir}/memory-batch/pending-id"
                "HERMES_APPROVAL_REQUESTS=${stateDir}/requests"
                "HERMES_APPROVAL_STATUS=${stateDir}/approval-status"
                "HERMES_REQUEST_BIN=${requestHelper}/bin/hermes-request"
              ];
              ExecStart = "${memoryBatch}/bin/hermes-memory-batch";
              UMask = "0007";
              NoNewPrivileges = true;
              PrivateNetwork = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = [
                memoryCheckout
                "${stateDir}/memory-batch"
                "${stateDir}/requests"
              ];
            };
          };

          hermes-snapshot-aggregate = {
            description = "Aggregate fleet observed snapshots for Hermes";
            requires = ["hermes-state-init.service"];
            after = ["network-online.target" "observed-snapshot.service" "hermes-state-init.service"];
            wants = ["network-online.target"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              ExecStart = lib.escapeShellArgs ([
                  "${aggregateSnapshot}/bin/hermes-snapshot-aggregate"
                  "${stateDir}/reports/current.json"
                  config.hermes.metricsUrl
                ]
                ++ config.hermes.peerAddresses);
            };
          };
        };

        timers = {
          hermes-memory-batch = {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = "*-*-* 04:00:00 UTC";
              Persistent = true;
            };
          };
          hermes-snapshot-aggregate = {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnBootSec = "7m";
              OnUnitActiveSec = "15m";
            };
          };
        };

        tmpfiles.rules = [
          "e ${stateDir}/reports/history - - - 7d"
          "e ${stateDir}/command-results - - - 30d"
          "e ${stateDir}/commands/cancel - - - 30d"
          "e ${stateDir}/commands/jobs - - - 30d"
          "e ${stateDir}/commands/processed - - - 30d"
          "e ${stateDir}/approval-status - - - 30d"
        ];
      };

      users = {
        users = {
          hermes = {
            extraGroups = ["hermes-publish" "hermes-requests" "hermes-results" "hermes-workspace"];
            homeMode = "751";
          };
          hermes-approval-broker = {
            isSystemUser = true;
            group = "hermes-approval-broker";
            home = "${stateDir}/publisher/home";
            createHome = false;
            extraGroups = ["hermes-publish" "hermes-requests" "hermes-results"];
          };
          hermes-command = {
            isSystemUser = true;
            group = "hermes-command";
            home = stateDir;
            createHome = false;
            extraGroups = ["hermes-publish" "hermes-results" "hermes-workspace"];
          };
        };
        groups = {
          hermes-approval-broker = {};
          hermes-command = {};
          hermes-publish = {};
          hermes-requests = {};
          hermes-results = {};
          hermes-workspace = {};
        };
      };
    };
  };
}
