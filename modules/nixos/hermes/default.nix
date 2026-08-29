{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.hermes = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hermes-agent;
    sopsFile = ./secrets.yaml;

    # Native mode sets HOME = stateDir, so this is the path hermes'
    # _import_codex_cli_tokens() reads as ~/.codex/auth.json.
    codexAuthDir = "${cfg.stateDir}/.codex";
    codexAuthPath = "${codexAuthDir}/auth.json";

    sshDir = "${cfg.stateDir}/.ssh";

    # accept-new (TOFU), not "no": a changed host key is still rejected after
    # the first connect; the operator can pre-seed known_hosts to skip TOFU.
    sshConfig = pkgs.writeText "hermes-ssh-config" (
      lib.concatMapStringsSep "\n\n" (node: ''
        Host ${node}
          HostName ${self.lib.legionNodes.${node}.privateIPv4}
          User hermes-ops
          IdentityFile ${sshDir}/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${sshDir}/known_hosts'')
      ["legion-node1" "legion-node2" "legion-node3" "legion-node4"]
      # Raw NetBird peer IP, not mesh DNS; must move together with
      # providers.artemis's base_url below if artemis's peer IP ever changes.
      + "\n\n"
      + ''
        Host artemis
          HostName 100.89.148.91
          User hermes-ops
          IdentityFile ${sshDir}/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${sshDir}/known_hosts''
    );

    calendarDir = "${cfg.stateDir}/.vdirsyncer/calendars";
    vdirsyncerStatusDir = "${cfg.stateDir}/.vdirsyncer/status";
    khalConfigDir = "${cfg.stateDir}/.config/khal";

    cronStoreDir = "${cfg.stateDir}/.hermes/cron";
    cronStoreTarget = "${cfg.workingDirectory}/knowledge-base/.hermes-cron";

    memoriesDir = "${cfg.stateDir}/.hermes/memories";
    memoriesTarget = "${cfg.workingDirectory}/knowledge-base/memories";

    contactsDir = "${cfg.stateDir}/.vdirsyncer/contacts";
    khardConfigDir = "${cfg.stateDir}/.config/khard";

    himalayaConfigDir = "${cfg.stateDir}/.config/himalaya";

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
      username.fetch = ["command", "printenv", "ICLOUD_USERNAME"]
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
      username.fetch = ["command", "printenv", "ICLOUD_USERNAME"]
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
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    services.hermes-agent = {
      enable = true;

      environmentFiles = [config.sops.secrets."hermes/env".path];

      environment = {
        ACTUAL_SERVER_URL = "http://172.17.0.4:${toString self.lib.ports.legion-node4.actual-budget}";
        GRAFANA_URL = "http://127.0.0.1:${toString self.lib.ports.legion-node3.grafana}";
        VDIRSYNCER_CONFIG = "${vdirsyncerConfig}";
      };

      settings = {
        model = {
          default = "gpt-5.6-luna";
          provider = "openai-codex";

          # Never codex_app_server: "auto" is the direct Responses API path.
          # Declared explicitly so the runtime /codex-runtime toggle can't
          # outlive a deploy (Nix-declared keys win the activation merge).
          openai_runtime = "auto";
        };
        agent = {
          reasoning_effort = "max";
          # Priority processing; declared so a runtime /fast --global toggle
          # can't outlive a deploy.
          service_tier = "fast";
        };

        memory = {
          # Upstream default, declared so a runtime /memory toggle can't
          # outlive a deploy.
          nudge_interval = 10;
          memory_char_limit = 4400;
          user_char_limit = 2750;
        };

        # Upstream default "local" lazy-installs faster-whisper; this
        # memory-capped node must never pull it.
        stt.provider = "groq";

        # Pinned so a later unrelated API key can't win the autodetect chain.
        web.backend = "brave-free";

        # Obscura CDP endpoint (the `obscura` unit below); agent-browser in
        # extraPackages is the driver CLI the browser_* tools shell out to.
        browser.cdp_url = "ws://127.0.0.1:9222";

        skills.external_dirs = ["${cfg.workingDirectory}/knowledge-base/skills"];

        # llama-swap on artemis over the NetBird mesh; manual switch only,
        # never part of the automatic fallback chain. Raw peer IP, not mesh
        # DNS -- must move together with the artemis Host block in sshConfig.
        providers.artemis = {
          base_url = "http://100.89.148.91:8080/v1";
          # Cold start after llama-swap's 30-minute TTL unload takes far
          # longer than a warm request.
          request_timeout_seconds = 600;
        };

        # Alertmanager -> Hermes: the agent investigates firing alerts and
        # reports to Telegram; investigate-and-report only, never
        # self-remediates.
        platforms.webhook = {
          enabled = true;
          extra = {
            host = "127.0.0.1";
            # Must match the literal in modules/nixos/monitoring/default.nix's
            # Alertmanager `webhook_configs.url`.
            port = 8644;
            routes.alertmanager = {
              # The adapter permits skipping HMAC only on a loopback bind.
              secret = "INSECURE_NO_AUTH";
              deliver = "telegram";
              prompt = ''
                A fleet alert fired via Alertmanager. Investigate before concluding anything -- don't just restate the payload.

                1. Read the alert(s) below: unit/node, condition, since when.
                2. Investigate: VictoriaLogs first (SERVERS.md "Logs: VictoriaLogs"), `systemctl status`/journalctl as fallback, VictoriaMetrics if it's a resource/threshold alert.
                3. Do NOT take any action from this turn -- no `systemctl restart`/`stop`, no `netbird expose`, no `sudo` command of any kind, not even a tier-1-safe one. This route is investigate-and-report only; it never self-remediates, regardless of how confident you are in a fix.
                4. End with a clear diagnosis for Aidan: what fired, what you found, and the specific action you'd recommend. This response IS the Telegram message he sees -- there's no separate step to send it. If he says go, the fix happens in the normal Telegram conversation, under the usual tier policy.

                Alertmanager payload:
                {__raw__}
              '';
            };
          };
        };
        # Overrides the deliberately-narrow webhook default toolset;
        # read-only investigation needs `terminal`.
        platform_toolsets.webhook = ["terminal"];
      };

      # Installed fresh into workingDirectory on every activation; in-place
      # self-edits by the agent never persist.
      documents = {
        "SERVERS.md" = ./SERVERS.md;
      };

      extraPackages = [
        pkgs.git
        pkgs.gh
        pkgs.curl
        pkgs.openssh
        pkgs.khal
        pkgs.vdirsyncer
        pkgs.khard
        pkgs.himalaya
        self.packages.${pkgs.stdenv.hostPlatform.system}.actual-cli
        self.packages.${pkgs.stdenv.hostPlatform.system}.agent-browser
      ];
    };

    sops.secrets = {
      # restartUnits: only hermes-agent -- listing the timer-driven oneshots
      # would instead fire a sync on every deploy; they read the file fresh.
      "hermes/env" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
      };
      # Codex-CLI-format OAuth seed; the upstream `authFile` option writes
      # Hermes' own store schema, not this shape, so preStart copies it to
      # the Codex-CLI path instead.
      "hermes/codex-auth.json" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
      };
      # Private half of the fleet key; the public half is committed at
      # modules/nixos/hermes-ops/default.nix's authorizedKeys.
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
        hermes-agent = {
          preStart = lib.mkAfter ''
            install -d -m 0700 "${codexAuthDir}"
            # Copy-if-absent: Hermes' own OAuth refresh rewrites this file
            # in place; clobbering it would lose a live token.
            if [ ! -f "${codexAuthPath}" ]; then
              install -m 0600 "${config.sops.secrets."hermes/codex-auth.json".path}" "${codexAuthPath}"
            fi

            # The runtime loads its persona from $HERMES_HOME/SOUL.md; the
            # `documents` option can't place files there.
            install -m 0640 ${./SOUL.md} "${cfg.stateDir}/.hermes/SOUL.md"

            install -d -m 0700 "${sshDir}"

            # Always overwrite (unlike codex-auth.json above): nothing on
            # this box mutates the key, and a rotated sops key must
            # propagate on the next deploy.
            install -m 0600 "${config.sops.secrets."hermes/ssh-key".path}" "${sshDir}/id_ed25519"
            install -m 0600 ${sshConfig} "${sshDir}/config"

            # khal has no config-path env var, only $HOME/.config/khal/config.
            install -d -m 0700 "${khalConfigDir}"
            install -m 0640 ${khalConfig} "${khalConfigDir}/config"

            # khard reads only $XDG_CONFIG_HOME/khard/khard.conf.
            install -d -m 0700 "${khardConfigDir}"
            install -m 0640 ${khardConfig} "${khardConfigDir}/khard.conf"

            # Rendered here (not pkgs.writeText) because backend.login needs
            # the sops-managed ICLOUD_MAIL_USERNAME: iCloud mail auth takes
            # the bare short name, NOT the full address CalDAV/CardDAV use.
            _icloud_mail_user=$(grep '^ICLOUD_MAIL_USERNAME=' "${config.sops.secrets."hermes/env".path}" | cut -d= -f2-)
            install -d -m 0700 "${himalayaConfigDir}"
            cat > "${himalayaConfigDir}/config.toml" <<EOF
            [accounts.icloud]
            default = true
            email = "aidan@aidanpinard.co"
            display-name = "Aidan Pinard"
            backend.type = "imap"
            backend.host = "imap.mail.me.com"
            backend.port = 993
            backend.encryption.type = "tls"
            backend.login = "$_icloud_mail_user"
            backend.auth.type = "password"
            backend.auth.cmd = "printenv ICLOUD_APP_PASSWORD"
            message.send.backend.type = "smtp"
            message.send.backend.host = "smtp.mail.me.com"
            message.send.backend.port = 587
            message.send.backend.encryption.type = "start-tls"
            message.send.backend.login = "$_icloud_mail_user"
            message.send.backend.auth.type = "password"
            message.send.backend.auth.cmd = "printenv ICLOUD_APP_PASSWORD"
            EOF
            chmod 0600 "${himalayaConfigDir}/config.toml"

            # Symlink the live-memory store into the KB clone so the
            # hermes-kb-sync timer makes it durable; the guard is a one-time
            # migration off a pre-symlink deploy's real directory.
            install -d "${memoriesTarget}"
            if [ -d "${memoriesDir}" ] && [ ! -L "${memoriesDir}" ]; then
              cp -a "${memoriesDir}/." "${memoriesTarget}/"
              rm -rf "${memoriesDir}"
            fi
            ln -sfn "${memoriesTarget}" "${memoriesDir}"

            # Same durability symlink for the cron store: scheduled routines
            # would otherwise be disposable state lost on a node rebuild.
            install -d "${cronStoreTarget}"
            if [ -d "${cronStoreDir}" ] && [ ! -L "${cronStoreDir}" ]; then
              cp -a "${cronStoreDir}/." "${cronStoreTarget}/"
              rm -rf "${cronStoreDir}"
            fi
            ln -sfn "${cronStoreTarget}" "${cronStoreDir}"
          '';

          serviceConfig = {
            MemoryHigh = "1536M";
            MemoryMax = "2G";
          };
        };

        # Headless CDP browser the browser_* tools attach to (browser.cdp_url
        # above). No --host flag exists to pin the bind address; port 9222 is
        # never opened in the firewall, so only loopback reaches it.
        obscura = {
          description = "Obscura headless CDP browser for Hermes";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            ExecStart = "${self.packages.${pkgs.stdenv.hostPlatform.system}.obscura}/bin/obscura serve --port 9222";
            DynamicUser = true;
            Restart = "on-failure";
            MemoryHigh = "384M";
            MemoryMax = "512M";
            # DynamicUser has no home; the engine needs writable scratch.
            CacheDirectory = "obscura";
            Environment = "HOME=%C/obscura";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        # The KB repo remote is the agent's only durable memory; the on-node
        # clone is disposable state re-created from it.
        hermes-kb-sync = {
          description = "Sync the Hermes Agent Knowledge Base repo";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          path = [pkgs.git pkgs.gh];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            EnvironmentFile = config.sops.secrets."hermes/env".path;
          };
          script = ''
            set -euo pipefail

            KB_DIR="${cfg.workingDirectory}/knowledge-base"

            export GIT_AUTHOR_NAME="Hermes Agent"
            export GIT_AUTHOR_EMAIL="hermes@jeiang.dev"
            export GIT_COMMITTER_NAME="Hermes Agent"
            export GIT_COMMITTER_EMAIL="hermes@jeiang.dev"

            # Clears any inherited helper, then installs gh's non-interactive
            # one (reads GITHUB_TOKEN from the environment).
            gitAuth () {
              git -c credential.helper= -c credential.helper='!gh auth git-credential' "$@"
            }

            # Not `git clone`: hermes-agent's preStart may have pre-populated
            # the directory (clone refuses it), and init+fetch+checkout also
            # heals a half-finished previous run.
            if [ ! -d "$KB_DIR/.git" ]; then
              install -d "$KB_DIR"
              git init -q -b main "$KB_DIR"
              git -C "$KB_DIR" remote add origin \
                https://github.com/jeiang/knowledge-base.git 2>/dev/null || true
              gitAuth -C "$KB_DIR" fetch origin main
              git -C "$KB_DIR" checkout -q -f -B main origin/main
              exit 0
            fi

            cd "$KB_DIR"

            # Commit anything the agent left uncommitted first, so the
            # rebase/push below never loses a concurrent agent write.
            git add -A
            if ! git diff --cached --quiet; then
              git commit -m "kb: auto-sync"
            fi

            gitAuth pull --rebase --autostash
            gitAuth push
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

            # discover prompts on stdin for each new remote collection and
            # has no --yes flag; a bounded y-feed (not `yes |`, which would
            # SIGPIPE under pipefail) keeps it non-interactive.
            printf 'y\n%.0s' $(seq 1 100) | vdirsyncer discover
            vdirsyncer sync
          '';
        };
      };

      timers = {
        hermes-kb-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            # OnUnitActiveSec alone never fires on a never-yet-active
            # service; OnActiveSec schedules the first run. Persistent=
            # applies only to OnCalendar= timers.
            OnActiveSec = "1m";
            OnUnitActiveSec = "15m";
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
