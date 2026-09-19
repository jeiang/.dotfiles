{
  self,
  inputs,
  ...
}: let
  # Matches the upstream default; kept as a literal so the NetBird-bind and
  # the WEBHOOK_ENABLED/WEBHOOK_PORT env story below stay in one place.
  hermesWebhookPort = 8644;
  kbRepo = "jeiang/knowledge-base";
  legionNodeNames = builtins.attrNames self.lib.legionNodes;
in {
  # Public half of the hermes/ssh-key secret below; modules/hermes-ops.nix's
  # authorizedKeys references this instead of a second hardcoded copy.
  # Placeholder until the operator mints the real ed25519 keypair.
  flake.lib.hermesOpsPublicKey = "ssh-ed25519 REPLACE_ME hermes-ops";

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
          context_length = 65536;
        };

        memory = {
          provider = "holographic";
          memory_char_limit = 4400;
          user_char_limit = 2750;
          nudge_interval = 10;
          write_approval = false;
        };

        web.backend = "brave-free";
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

        skills.external_dirs = ["${kbExportDir}/skills"];

        platforms.webhook = {
          enabled = true;
          extra = {
            host = self.lib.netbirdPeers.artemis;
            port = hermesWebhookPort;
          };
        };
        # No routes are wired yet (a later PR adds a Jev gate in front of
        # one); this only shapes the adapter and its toolset ahead of that.
        platform_toolsets.webhook = ["terminal"];
      };

      hermesHomeFiles."SOUL.md" = ./SOUL.md;
      documents."SERVERS.md" = ./SERVERS.md;

      extraPackages = [pkgs.gh pkgs.openssh pkgs.sqlite];
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
    };

    systemd = {
      services = {
        hermes-agent.preStart = lib.mkAfter ''
          install -d -m 0700 -o ${cfg.user} -g ${cfg.group} ${sshDir}
          install -m 0600 -o ${cfg.user} -g ${cfg.group} ${config.sops.secrets."hermes/ssh-key".path} ${sshDir}/id_ed25519
          install -m 0600 -o ${cfg.user} -g ${cfg.group} ${sshConfig} ${sshDir}/config
        '';

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
      };

      timers.hermes-kb-export = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "weekly";
          RandomizedDelaySec = "2h";
          Persistent = true;
        };
      };
    };
  };
}
