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
    codexConfig = pkgs.writeText "hermes-codex-config.toml" ''
      sandbox_mode = "workspace-write"
      approval_policy = "on-request"
      model = "gpt-5.6-terra"
      model_reasoning_effort = "medium"

      [sandbox_workspace_write]
      writable_roots = ["${workspace}"]
      network_access = false
    '';
    repositoriesFile = pkgs.writeText "hermes-publisher-repositories.json" (builtins.toJSON config.hermes.publisherRepositories);
    publisher = pkgs.writeShellApplication {
      name = "hermes-publisher";
      runtimeInputs = [pkgs.gh pkgs.git pkgs.python3];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-publisher.py} "$@"
      '';
    };
    aggregateSnapshot = pkgs.writers.writePython3Bin "hermes-snapshot-aggregate" {flakeIgnore = ["E501"];} (builtins.readFile ./hermes-snapshot-aggregate.py);
    hermesSettings = {
      model = {
        provider = "openai-codex";
        default = "gpt-5.6-terra";
        openai_runtime = "codex_app_server";
      };
      fallback_providers = [];
      timezone = "America/Port_of_Spain";
      agent.reasoning_effort = "medium";
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        write_approval = false;
      };
      skills.write_approval = true;
      unauthorized_dm_behavior = "ignore";
      gateway.platforms.telegram.extra = {
        # The SOPS environment file supplies TELEGRAM_ALLOWED_USERS. Hermes
        # treats an empty allowlist as unrestricted. Telegram group IDs are
        # numeric, so this impossible nonempty entry denies every group while
        # direct-message authorization stays environment-based.
        allowed_chats = ["__hermes_dm_only__"];
        group_allowed_chats = [];
        guest_mode = false;
        observe_unmentioned_group_messages = false;
      };
    };
    # config.yaml is exactly `builtins.toJSON settings` upstream (JSON is valid
    # YAML); reproduced here so hermes-state-init can install it post-mount.
    hermesConfig = pkgs.writeText "hermes-config.yaml" (builtins.toJSON hermesSettings);
    # The agent and Codex run plain pkgs.git, which refuses the mirrors as
    # "dubious ownership" (they belong to hermes-publisher). Mark exactly the
    # mirror paths safe in the hermes home gitconfig — HOME is the volume root,
    # so this covers every git the agent spawns without a global config write.
    mirrorPath = repo: "${stateDir}/mirrors/${builtins.replaceStrings ["/"] ["__"] repo}.git";
    hermesGitconfig = pkgs.writeText "hermes-gitconfig" ''
      [safe]
      ${lib.concatMapStringsSep "\n" (repo: "\tdirectory = ${mirrorPath repo}") (builtins.attrNames config.hermes.publisherRepositories)}
    '';
    # The persistent state lives on a nofail Hetzner Volume that mounts after
    # both systemd-tmpfiles-setup and the system activation script that the
    # upstream module uses to create ${stateDir}/.hermes, config.yaml, and
    # .env. Those all run pre-mount, so their output lands on the shadowed
    # pre-mount mountpoint and the volume root stays root:root and empty. This
    # oneshot runs after the mount, in the host namespace, and is the single
    # authority for the on-volume layout: it owns the volume root as the hermes
    # home, recreates the agent's ~/.hermes tree with config.yaml and .env, and
    # creates the publisher/mirror/report directories the sandboxed services
    # build their namespaces against.
    stateInit = pkgs.writeShellApplication {
      name = "hermes-state-init";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        # Agent home == volume root; 0751 keeps it traversable by the
        # publisher (hermes-publish group / other) without granting write.
        install -d -o hermes -g hermes -m 0751 ${stateDir}
        install -d -o hermes -g hermes -m 2770 ${stateDir}/.hermes
        for sub in cron sessions logs memories plugins; do
          install -d -o hermes -g hermes -m 2770 "${stateDir}/.hermes/$sub"
        done
        install -d -o hermes -g hermes -m 0750 ${stateDir}/home
        install -o hermes -g hermes -m 0640 ${hermesConfig} ${stateDir}/.hermes/config.yaml
        install -o hermes -g hermes -m 0640 ${config.sops.secrets."hermes/env".path} ${stateDir}/.hermes/.env
        install -o hermes -g hermes -m 0640 ${hermesGitconfig} ${stateDir}/.gitconfig

        install -d -o hermes            -g hermes           -m 0700 ${stateDir}/codex
        install -d -o hermes-publisher  -g hermes-publisher -m 0750 ${stateDir}/publisher
        install -d -o hermes-publisher  -g hermes-publisher -m 0700 ${stateDir}/publisher/home
        install -d -o hermes-publisher  -g hermes-publisher -m 0700 ${stateDir}/publisher/gh
        install -d -o hermes-publisher  -g hermes-publisher -m 0750 ${stateDir}/publisher/completed
        install -d -o hermes-publisher  -g hermes-publisher -m 0750 ${stateDir}/publisher/rejected
        install -d -o hermes-publisher  -g hermes-publish   -m 0750 ${stateDir}/mirrors
        install -d -o hermes            -g hermes-publish   -m 0750 ${workspace}
        install -d -o hermes            -g hermes-publish   -m 2770 ${workspace}/.publisher-requests
        install -d -o root              -g hermes           -m 0750 ${stateDir}/reports
        install -d -o root              -g hermes           -m 0750 ${stateDir}/reports/history
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
        description = "Only directory writable to Codex app-server turns.";
      };
      peerAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Private addresses whose observed snapshots are aggregated.";
      };
      metricsUrl = lib.mkOption {
        type = lib.types.str;
        description = "VictoriaMetrics base URL queried by the aggregator.";
      };
      publisherRepositories = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          "jeiang/.dotfiles" = "${config.hermes.workspace}/cornn-flaek";
          "jeiang/knowledge-base" = "${config.hermes.workspace}/knowledge-base";
        };
        description = "Publication policy: repository to approved worktree path.";
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
          owner = "hermes-publisher";
          group = "hermes-publisher";
          mode = "0400";
        };
      };

      services.hermes-agent = {
        enable = true;
        inherit stateDir;
        workingDirectory = workspace;
        # No authFile: model turns run through the `codex app-server`
        # subprocess, which authenticates from CODEX_HOME/auth.json (the
        # hermes/codex-auth.json seed). Hermes' own ~/.hermes/auth.json
        # store is only used by the default (non-Codex) runtime, which
        # this deployment never selects (openai_runtime = codex_app_server,
        # fallback_providers = []).
        environmentFiles = [config.sops.secrets."hermes/env".path];
        extraDependencyGroups = ["messaging"];
        extraPackages = [pkgs.codex];
        # The upstream activation script also renders this to config.yaml, but
        # pre-mount (shadowed); hermes-state-init reinstalls the same content
        # onto the volume. Kept here so the module's own settings-aware logic
        # (e.g. mcp_servers merge) still sees the configuration.
        settings = hermesSettings;
      };

      systemd = {
        services = {
          hermes-state-init = {
            description = "Create Hermes state directories on the mounted volume";
            wantedBy = ["multi-user.target"];
            before = ["hermes-agent.service" "hermes-publisher.service" "hermes-snapshot-aggregate.service"];
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
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Environment = [
                "CODEX_HOME=${stateDir}/codex"
                "TZ=America/Port_of_Spain"
                # This node has working DNS and direct reachability to
                # api.telegram.org, so the adapter's DoH-discovered fallback-IP
                # transport is pure downside here: it wedged startup
                # indefinitely on an unreachable fallback chain. Force the
                # direct httpx client instead.
                "HERMES_TELEGRAM_DISABLE_FALLBACK_IPS=1"
              ];
              MemoryMax = "1G";
              CPUQuota = "100%";
              ExecStartPre = lib.mkAfter [
                "+${pkgs.coreutils}/bin/install -d -o hermes -g hermes -m 0700 ${stateDir}/codex"
                "+${pkgs.bash}/bin/sh -c 'test -s ${stateDir}/codex/auth.json || ${pkgs.coreutils}/bin/install -o hermes -g hermes -m 0600 ${config.sops.secrets."hermes/codex-auth.json".path} ${stateDir}/codex/auth.json'"
                "+${pkgs.coreutils}/bin/install -o hermes -g hermes -m 0640 ${codexConfig} ${stateDir}/codex/config.toml"
              ];
            };
          };

          hermes-publisher = {
            description = "Hermes GitHub publication approval broker";
            wantedBy = ["multi-user.target"];
            requires = ["hermes-state-init.service"];
            after = ["network-online.target" "hermes-state-init.service"];
            wants = ["network-online.target"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              User = "hermes-publisher";
              Group = "hermes-publisher";
              Environment = [
                "HOME=${stateDir}/publisher/home"
                "GH_CONFIG_DIR=${stateDir}/publisher/gh"
                "HERMES_PUBLISHER_PENDING=${workspace}/.publisher-requests"
                "HERMES_PUBLISHER_MIRRORS=${stateDir}/mirrors"
                "HERMES_PUBLISHER_REPOSITORIES_FILE=${repositoriesFile}"
              ];
              EnvironmentFile = config.sops.secrets."hermes/publisher-env".path;
              ExecStart = "${publisher}/bin/hermes-publisher ${stateDir}/publisher";
              Restart = "always";
              RestartSec = "5s";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = [
                "${stateDir}/publisher"
                "${stateDir}/mirrors"
                "${workspace}/.publisher-requests"
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
        timers.hermes-snapshot-aggregate = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "7m";
            OnUnitActiveSec = "15m";
          };
        };

        # Directory creation is handled by hermes-state-init (post-mount, in
        # the host namespace) because these paths live on a nofail Volume that
        # mounts after systemd-tmpfiles-setup. The agent owns its worktrees
        # outright (single-writer .git); the publisher only reads them, via the
        # hermes-publish group; the publisher's own tree and the bare mirrors
        # are publisher-owned so the agent cannot swap out directories feeding
        # the credentialed git/gh processes. tmpfiles only ages out the
        # snapshot history here (the `e` type never creates, so it is immune to
        # the mount-ordering race above).
        tmpfiles.rules = [
          "e ${stateDir}/reports/history - - - 7d"
        ];
      };

      users = {
        users.hermes = {
          extraGroups = ["hermes-publish"];
          # The state directory is also the hermes home; the default 0700
          # home mode would keep the publisher from traversing to the
          # worktrees, mirrors, and pending-request directories beneath it.
          homeMode = "751";
        };
        users.hermes-publisher = {
          isSystemUser = true;
          group = "hermes-publisher";
          home = "${stateDir}/publisher/home";
          createHome = false;
          extraGroups = ["hermes-publish"];
        };
        groups = {
          hermes-publisher = {};
          hermes-publish = {};
        };
      };
    };
  };
}
