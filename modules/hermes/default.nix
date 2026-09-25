{
  self,
  inputs,
  ...
}: let
  # Matches the upstream default; kept as a literal so the bind and the
  # WEBHOOK_ENABLED/WEBHOOK_PORT env story below stay in one place.
  hermesWebhookPort = 8644;
  kbRepo = "jeiang/knowledge-base";
  legionNodeNames = builtins.attrNames self.lib.legionNodes;
  # Not a secret: it's the CalDAV/CardDAV/IMAP display identity, shared by
  # the himalaya and vdirsyncer config below.
  icloudAppleId = "aidan@aidanpinard.co";
in {
  # Public half of the hermes/ssh-key secret below.
  flake.lib.hermesOpsPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICMV+ek2SZ1bRHNHs6/CKpS6p+xaRR6FW69eXDGwH3pr hermes-ops";

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hermes-agent;
    sopsFile = ./secrets.yaml;

    hermesHome = "${cfg.stateDir}/.hermes";
    sshDir = "${cfg.stateDir}/.ssh";

    # Workaround: the upstream module installs config.yaml, .env and the
    # documents from a system activation script, but artemis activates from
    # the initrd, before the impermanence bind mount of stateDir exists. Those
    # writes land on the root subvolume, get hidden by the mount, and are
    # nuked on the next boot, so the gateway starts with neither its settings
    # nor its secrets. Re-running the module's own state script before the
    # gateway starts puts the same files on the mounted directory.
    #
    # It has to run as root: on a live switch the activation script runs after
    # the mount and leaves config.yaml root-owned, because mkStateScript writes
    # that one file through its merge script and never chowns it. The script is
    # therefore a "+" ExecStartPre, and it chowns config.yaml itself so the
    # gateway, which rewrites the file at runtime, owns it.
    hermesCommon = import "${inputs.hermes-agent}/nix/moduleCommon.nix" {inherit lib;};
    hermesStateScript = pkgs.writeShellScript "hermes-render-state" ''
      set -e

      ${hermesCommon.mkStateScript {
        inherit pkgs cfg hermesHome;
        inherit (cfg) workingDirectory;
        owner = "${cfg.user}:${cfg.group}";
        stateDirs = hermesCommon.stateSubdirs;
        modes = {
          config = "0640";
          env = "0640";
          managed = "0644";
          auth = "0600";
          document = "0640";
        };
      }}

      chown ${cfg.user}:${cfg.group} ${hermesHome}/config.yaml
    '';

    # artemis has no Hetzner private-network route to Legion; every hop is
    # over NetBird, so hermes-ops is reached at each peer's mesh address
    # (modules/netbird-peers.nix), not the 172.17.0.0/24 Hetzner IPs the
    # Legion nodes use to reach each other.
    sshConfig = pkgs.writeText "hermes-ssh-config" (
      lib.concatMapStringsSep "\n\n" (node: ''
        Host ${node}
          HostName ${self.lib.netbirdPeers.${node}}
          User hermes-ops
          IdentityFile ${sshDir}/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${sshDir}/known_hosts'')
      legionNodeNames
    );

    kbExportDir = "${cfg.workingDirectory}/knowledge-base-export";

    configDir = "${cfg.stateDir}/.config";
    himalayaConfigDir = "${configDir}/himalaya";

    calendarDir = "${cfg.stateDir}/.vdirsyncer/calendars";
    contactsDir = "${cfg.stateDir}/.vdirsyncer/contacts";
    vdirsyncerStatusDir = "${cfg.stateDir}/.vdirsyncer/status";
    khalConfigDir = "${configDir}/khal";
    khardConfigDir = "${configDir}/khard";

    vdirsyncerConfig = pkgs.writeText "hermes-vdirsyncer-config" ''
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

    khalConfig = pkgs.writeText "hermes-khal-config" ''
      [calendars]
      [[icloud]]
      path = ${calendarDir}/*
      type = discover
    '';

    khardConfig = pkgs.writeText "hermes-khard-config" ''
      [addressbooks]
      [[icloud]]
      path = ${contactsDir}/*
      type = discover
    '';

    grafanaMcp = pkgs.writeShellScript "hermes-mcp-grafana" ''
      GRAFANA_SERVICE_ACCOUNT_TOKEN=$(<${config.sops.secrets."hermes/grafana-token".path})
      export GRAFANA_SERVICE_ACCOUNT_TOKEN
      exec ${lib.getExe pkgs.mcp-grafana} -disable-write "$@"
    '';

    agentSkillNames = ["eli5" "grilling" "i-have-adhd" "research"];
    agentSkillsTree = inputs.agent-skills.packages.${pkgs.stdenv.hostPlatform.system}.omp-personal;
    agentSkills = assert lib.subtractLists inputs.agent-skills.lib.entries.omp.personal.skills agentSkillNames == [];
      pkgs.linkFarm "hermes-agent-skills" (map (name: {
          inherit name;
          path = "${agentSkillsTree}/skills/${name}";
        })
        agentSkillNames);
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    services.hermes-agent = {
      enable = true;
      stateDir = "/var/lib/hermes";
      # Documents (SERVERS.md) need an explicit selection or the module
      # refuses the config; this is the module's own default value, made
      # explicit.
      workingDirectory = "${cfg.stateDir}/workspace";

      environmentFiles = [config.sops.secrets."hermes/env".path];
      # The webhook adapter only merges WEBHOOK_SECRET out of the process
      # environment when WEBHOOK_ENABLED is itself an env var (gateway
      # config_env.py); the secret can otherwise only reach config.yaml as
      # a literal, which would land in the Nix store.
      environment.WEBHOOK_ENABLED = "true";

      settings = {
        model = {
          default = self.lib.llmServerModelId;
          provider = "custom";
          base_url = "http://127.0.0.1:${toString self.lib.llmServerPort}/v1";
          context_length = self.lib.llmServerContextLength;
        };

        memory = {
          provider = "holographic";
          memory_char_limit = 4400;
          user_char_limit = 2750;
          nudge_interval = 10;
          write_approval = false;
        };

        # Deterministic, no-LLM prune of old tool results: each LLM summary
        # on the local model stalls the chat for minutes.
        compression = {
          proactive_prune_tokens = 60000;
          proactive_prune_min_result_chars = 4000;
          proactive_prune_min_reclaim_tokens = 8192;
          min_tail_user_messages = 2;
        };
        tool_output = {
          max_bytes = 16000;
          max_lines = 600;
        };
        # Summaries on the local model outrun the 120 s default; the review
        # replays the conversation on the same GPU, so its input is capped.
        auxiliary = {
          compression.timeout = 300;
          background_review.max_input_tokens = 100000;
        };

        streaming = {
          enabled = true;
          transport = "auto";
        };
        display.platforms.telegram.streaming = true;

        # Local hygiene only: the pattern check and its guardian (the local
        # model) are in-process and bypassable. Tier 2 is gated by
        # hermes-approver, not by these.
        approvals = {
          smart_policy = "Legion sudoers enforce the tier-1 allowlist, so APPROVE `ssh legion-nodeN -- sudo systemctl start|restart <unit>.service`. ESCALATE anything that stops, disables or masks a unit, writes under /etc, or pipes downloaded content to a shell.";
          deny = ["*nixos-rebuild*" "*sops -d*"];
        };

        web = {
          backend = "brave-free";
          # brave-free cannot extract; with no EXA_API_KEY this is Exa's keyless tier.
          extract_backend = "exa";
          extract_char_limit = 8000;
        };
        stt.provider = "groq";

        # ~20 tools: drops browser (no Obscura), image/tts generation, home
        # assistant, kanban and computer-use. AGENTS.md hermes-ops decision.
        agent.disabled_toolsets = [
          "browser"
          "image_gen"
          "tts"
          "homeassistant"
          "kanban"
          "computer_use"
        ];

        skills.external_dirs = ["${kbExportDir}/skills" "${agentSkills}"];

        platforms.webhook = {
          enabled = true;
          extra = {
            # The mesh address appears only once NetBird is up, and the adapter
            # binds once at start. No port is opened for it, so only the
            # trusted NetBird interface and loopback reach it.
            host = "0.0.0.0";
            port = hermesWebhookPort;
          };
        };
        # The webhook routes are declared in modules/hermes/jev.
        platform_toolsets.webhook = ["terminal"];
      };

      mcpServers = {
        nixos.command = lib.getExe pkgs.mcp-nixos;
        grafana = {
          command = "${grafanaMcp}";
          env.GRAFANA_URL = self.lib.grafanaMeshUrl;
        };
        # Tokens live in $HERMES_HOME/mcp-tokens; the first login is an interactive `hermes mcp login notion`.
        notion = {
          url = "https://mcp.notion.com/mcp";
          auth = "oauth";
          tools.include = [
            "notion-search"
            "notion-fetch"
            "notion-query-data-sources"
            "notion-list-recent-pages"
            "notion-get-comments"
            "notion-create-pages"
            "notion-update-page"
            "notion-create-comment"
          ];
        };
      };

      hermesHomeFiles."SOUL.md" = ./SOUL.md;
      documents."SERVERS.md" = ./SERVERS.md;

      extraPackages = [pkgs.gh pkgs.openssh pkgs.sqlite pkgs.himalaya pkgs.vdirsyncer pkgs.khal pkgs.khard];
    };

    sops.secrets = {
      "hermes/env" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
      };
      "hermes/ssh-key" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
      };
      "hermes/grafana-token" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
      };
    };

    systemd = {
      services = {
        hermes-agent = {
          serviceConfig.ExecStartPre = lib.mkBefore ["+${hermesStateScript}"];

          preStart = lib.mkAfter ''
            install -d -m 0700 -o ${cfg.user} -g ${cfg.group} ${sshDir}
            install -m 0600 -o ${cfg.user} -g ${cfg.group} ${config.sops.secrets."hermes/ssh-key".path} ${sshDir}/id_ed25519
            install -m 0600 -o ${cfg.user} -g ${cfg.group} ${sshConfig} ${sshDir}/config

            # Rendered here, not pkgs.writeText: the IMAP username comes from
            # the sops-managed ICLOUD_MAIL_USERNAME. iCloud IMAP auth takes the
            # bare short name, not the Apple ID that email/CalDAV/CardDAV use.
            # No smtp block: sending is mechanically unavailable, not just a
            # SOUL.md rule.
            _icloud_mail_user=$(grep '^ICLOUD_MAIL_USERNAME=' "${config.sops.secrets."hermes/env".path}" | cut -d= -f2-)
            install -d -m 0700 -o ${cfg.user} -g ${cfg.group} ${himalayaConfigDir}
            cat > ${himalayaConfigDir}/config.toml <<EOF
            [accounts.icloud]
            default = true
            email = "${icloudAppleId}"
            display-name = "Aidan Pinard"

            [accounts.icloud.imap]
            server = "imap.mail.me.com:993"
            tls = {}

            [accounts.icloud.imap.sasl.plain]
            username = "$_icloud_mail_user"
            password.cmd = "printenv ICLOUD_APP_PASSWORD"
            EOF
            chown ${cfg.user}:${cfg.group} ${himalayaConfigDir}/config.toml
            chmod 0600 ${himalayaConfigDir}/config.toml

            # khal has no config-path env var, only $HOME/.config/khal/config.
            install -d -m 0700 -o ${cfg.user} -g ${cfg.group} ${khalConfigDir}
            install -m 0640 -o ${cfg.user} -g ${cfg.group} ${khalConfig} ${khalConfigDir}/config

            # khard reads only $XDG_CONFIG_HOME/khard/khard.conf.
            install -d -m 0700 -o ${cfg.user} -g ${cfg.group} ${khardConfigDir}
            install -m 0640 -o ${cfg.user} -g ${cfg.group} ${khardConfig} ${khardConfigDir}/khard.conf
          '';
        };

        hermes-kb-export = {
          description = "Weekly one-way export of Hermes memory into the knowledge-base repo";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.git pkgs.gh pkgs.sqlite pkgs.findutils pkgs.coreutils];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            EnvironmentFile = config.sops.secrets."hermes/env".path;
          };
          script = ''
            set -euo pipefail

            export GIT_AUTHOR_NAME="Hermes Agent"
            export GIT_AUTHOR_EMAIL="hermes@jeiang.dev"
            export GIT_COMMITTER_NAME="Hermes Agent"
            export GIT_COMMITTER_EMAIL="hermes@jeiang.dev"

            gitAuth () {
              git -c credential.helper= -c credential.helper='!gh auth git-credential' "$@"
            }

            if [ ! -d "${kbExportDir}/.git" ]; then
              install -d "${kbExportDir}"
              git init -q -b main "${kbExportDir}"
              git -C "${kbExportDir}" remote add origin "https://github.com/${kbRepo}.git" 2>/dev/null || true
            fi

            # One-way: always reset onto the remote's current state before writing
            # this run's snapshot. Nothing exported here is ever read back into
            # Hermes' own memory.
            gitAuth -C "${kbExportDir}" fetch origin main
            git -C "${kbExportDir}" checkout -q -B main origin/main 2>/dev/null || git -C "${kbExportDir}" checkout -q -B main

            install -d "${kbExportDir}/journal" "${kbExportDir}/self-actions" "${kbExportDir}/facts"

            stamp="$(date -u +%Y-%m-%d)"

            if [ -f "${hermesHome}/memories/MEMORY.md" ]; then
              install -m 0644 "${hermesHome}/memories/MEMORY.md" "${kbExportDir}/journal/$stamp-MEMORY.md"
            fi

            if [ -f "${hermesHome}/memory_store.db" ]; then
              sqlite3 "${hermesHome}/memory_store.db" .dump > "${kbExportDir}/facts/$stamp-memory_store.sql" || true
            fi

            # Best-effort digest, not a real action log: a session filename tells
            # you a session happened, not what it did on its own initiative.
            find "${hermesHome}/sessions" -maxdepth 1 -type f -mtime -7 -printf '%f\n' 2>/dev/null \
              | sort >"${kbExportDir}/self-actions/$stamp-sessions.txt" || true

            cd "${kbExportDir}"
            git add -A
            if ! git diff --cached --quiet; then
              git commit -q -m "kb: weekly export $stamp"
              gitAuth push origin main
            fi
          '';
        };

        hermes-vdirsyncer-sync = {
          description = "Sync Hermes' iCloud calendar and contacts via vdirsyncer";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.vdirsyncer];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            EnvironmentFile = config.sops.secrets."hermes/env".path;
            Environment = "VDIRSYNCER_CONFIG=${vdirsyncerConfig}";
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
        hermes-kb-export = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "weekly";
            RandomizedDelaySec = "2h";
            Persistent = true;
          };
        };

        hermes-vdirsyncer-sync = {
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
