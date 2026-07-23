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
    publisher = pkgs.writeShellApplication {
      name = "hermes-publisher";
      runtimeInputs = [pkgs.gh pkgs.git pkgs.python3];
      text = ''
        exec ${pkgs.python3}/bin/python ${./hermes-publisher.py}
      '';
    };
    aggregateSnapshot = pkgs.writers.writePython3Bin "hermes-snapshot-aggregate" {} (builtins.readFile ./hermes-snapshot-aggregate.py);
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
    };

    config = lib.mkIf config.hermes.enable {
      sops.secrets = {
        "hermes/env" = {
          owner = "hermes";
          group = "hermes";
          mode = "0400";
        };
        "hermes/auth.json" = {
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
        authFile = config.sops.secrets."hermes/auth.json".path;
        environmentFiles = [config.sops.secrets."hermes/env".path];
        extraDependencyGroups = ["messaging"];
        extraPackages = [pkgs.codex];
        settings = {
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
            # The SOPS environment file supplies TELEGRAM_ALLOWED_USERS.
            # Hermes treats an empty allowlist as unrestricted. Telegram group
            # IDs are numeric, so this impossible nonempty entry denies every
            # group while direct-message authorization stays environment-based.
            allowed_chats = ["__hermes_dm_only__"];
            group_allowed_chats = [];
            guest_mode = false;
            observe_unmentioned_group_messages = false;
          };
        };
      };

      systemd = {
        services = {
          hermes-agent = {
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Environment = [
                "CODEX_HOME=${stateDir}/codex"
                "TZ=America/Port_of_Spain"
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
            after = ["network-online.target"];
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
              ];
              EnvironmentFile = config.sops.secrets."hermes/publisher-env".path;
              ExecStart = "${publisher}/bin/hermes-publisher ${stateDir}/publisher";
              Restart = "always";
              RestartSec = "5s";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = ["${stateDir}/publisher" workspace];
            };
          };

          hermes-snapshot-aggregate = {
            description = "Aggregate fleet observed snapshots for Hermes";
            after = ["network-online.target" "observed-snapshot.service"];
            wants = ["network-online.target"];
            unitConfig = {
              ConditionPathIsMountPoint = stateDir;
              RequiresMountsFor = stateDir;
            };
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              ExecStart = "${aggregateSnapshot}/bin/hermes-snapshot-aggregate ${stateDir}/reports/current.json 172.17.0.1 172.17.0.2 172.17.0.3 172.17.0.4";
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

        tmpfiles.rules = [
          "d ${stateDir}/codex 0700 hermes hermes - -"
          "d ${stateDir}/publisher 2770 hermes hermes-publish - -"
          "d ${stateDir}/publisher/home 0700 hermes-publisher hermes-publisher - -"
          "d ${stateDir}/publisher/gh 0700 hermes-publisher hermes-publisher - -"
          "d ${workspace} 2770 hermes hermes-publish - -"
          "d ${workspace}/.publisher-requests 2770 hermes hermes-publish - -"
          "d ${stateDir}/publisher/completed 0750 hermes-publisher hermes-publisher - -"
          "d ${stateDir}/publisher/rejected 0750 hermes-publisher hermes-publisher - -"
          "d ${stateDir}/reports 0750 root hermes - -"
          "d ${stateDir}/reports/history 0750 root hermes 7d -"
        ];
      };

      users = {
        users.hermes = {
          extraGroups = ["hermes-publish"];
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
