{inputs, ...}: {
  # Hermes Agent (CONTEXT.md "Hermes Agent" -- the personal agent Host-Native
  # Service the fleet runs, consuming the upstream hermes-agent NixOS module
  # directly). Imported only for the inventory node placing `hermes` (piece
  # 4, legion-node3 today, same optional-import pattern as
  # modules/nixos/attic.nix / actual-budget.nix in
  # modules/hosts/legion/default.nix) -- this module never enables itself on
  # a host by importing.
  #
  # `inputs.hermes-agent` is pinned at flake.nix, deliberately not following
  # our nixpkgs (see that input's comment). Everything below is checked
  # against `nix/nixosModules.nix` at the pinned rev
  # (cc4cab2f592e60a197e796506de9168f74baf3ea) -- fetched via
  # `gh api repos/NousResearch/hermes-agent/contents/...` rather than
  # trusted from memory, since this module is the only consumer of options
  # that file defines.
  #
  # Native (non-container) systemd mode throughout:
  # `services.hermes-agent.container.enable` is left at its upstream default
  # (`false`), so the service runs as a plain systemd unit under the `hermes`
  # user (upstream default `user`/`group`/`createUser`, all left at their
  # defaults here) rather than in a Docker/Podman OCI container -- there is
  # no need for the container's writable-apt-layer story on a fleet node
  # that only needs git/gh/curl (extraPackages below cover that from the
  # Nix store instead).
  flake.nixosModules.hermes = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hermes-agent;
    sopsFile = ../sops/secrets.hermes.yaml;

    # Native mode's systemd unit sets `environment.HOME = cfg.stateDir`
    # (nix/nixosModules.nix, the "MODE A: Native systemd service" block) --
    # confirmed at the pinned rev, not assumed. hermes_cli/auth.py's
    # `_import_codex_cli_tokens()` resolves the Codex-CLI-shared auth file
    # via `Path.home() / ".codex" / "auth.json"` when `$CODEX_HOME` is
    # unset (it is unset here), so `${cfg.stateDir}/.codex/auth.json` is the
    # exact path that function reads. Computed from `cfg.stateDir` directly
    # (not `$HOME`) so the preStart script below doesn't depend on that env
    # var actually reaching the shell unchanged.
    codexAuthDir = "${cfg.stateDir}/.codex";
    codexAuthPath = "${codexAuthDir}/auth.json";
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    services.hermes-agent = {
      enable = true;

      # sops-fed secrets/env (below) merge into $HERMES_HOME/.env via the
      # upstream activation script -- see the `sops.secrets` block.
      environmentFiles = [config.sops.secrets."hermes/env".path];

      # gpt-5.6-luna is in Hermes' supported Codex model list
      # (hermes_cli/codex_models.py `CODEX_SUPPORTED_MODELS` at the pinned
      # rev) served through the "openai-codex" provider
      # (cli-config.yaml.example's documented provider enum, same rev).
      settings = {
        model = {
          default = "gpt-5.6-luna";
          provider = "openai-codex";

          # CRITICAL -- pinned explicitly, not left at the upstream default
          # (which happens to also be "auto", but declaring it here is what
          # makes the pin durable). "auto" means Hermes' own agent loop
          # calls the model directly over the Codex Responses API
          # (agent/codex_runtime.py `run_codex_stream`, the `codex_responses`
          # api_mode). The alternative, "codex_app_server", hands each turn
          # to a `codex app-server` CLI subprocess instead (the harness) --
          # this deployment must never run that mode.
          #
          # hermes_cli/codex_runtime_switch.py persists a `/codex-runtime`
          # slash-command toggle into this exact `model.openai_runtime` key
          # in $HERMES_HOME/.hermes/config.yaml. Upstream's own activation
          # script (`configMergeScript`) deep-merges the Nix-generated
          # config over the *existing* on-disk one and lets Nix-declared
          # keys win, but only for keys Nix actually declares -- an
          # undeclared key an operator toggled at runtime would otherwise
          # survive every redeploy untouched. Declaring `openai_runtime`
          # here makes every activation re-assert "auto", so the toggle
          # can't persist past a deploy.
          openai_runtime = "auto";
        };
        agent.reasoning_effort = "medium";
      };

      # SOUL.md/SERVERS.md are colocated with this module (documents values
      # may be paths -- nix/nixosModules.nix `documentDerivation`) and get
      # installed fresh into workingDirectory on EVERY activation, so
      # in-place self-edits by the agent never persist; see the note at the
      # top of SOUL.md.
      documents = {
        "SOUL.md" = ./SOUL.md;
        "SERVERS.md" = ./SERVERS.md;
      };

      # git/gh: the agent's own terminal tool needs them for GitHub access
      # and for the Knowledge Base repo (also used by hermes-kb-sync below,
      # which needs its own explicit `path` since it's a separate systemd
      # unit and doesn't inherit this list). curl: querying
      # VictoriaMetrics/VictoriaLogs per SERVERS.md. Wired onto both the
      # `hermes` user's per-user profile PATH and this service's own
      # systemd PATH (nix/nixosModules.nix `extraPackages` option).
      extraPackages = [pkgs.git pkgs.gh pkgs.curl];
    };

    # Do NOT use the upstream `authFile` option here: it seeds
    # `${cfg.stateDir}/.hermes/auth.json`, i.e. Hermes' own multi-provider
    # auth-store schema (`providers.<name>.tokens` plus bookkeeping fields --
    # hermes_cli/auth.py `_save_codex_tokens`/`_load_provider_state`), not
    # the flat `{"tokens": {access_token, refresh_token, ...}}` shape a real
    # `~/.codex/auth.json` (Codex CLI's own file) contains. The sops secret
    # "hermes/codex-auth.json" is in that Codex-CLI shape, so it has to land
    # at the Codex-CLI path instead -- `${cfg.stateDir}/.codex/auth.json` --
    # which `_import_codex_cli_tokens()` reads directly (see `codexAuthPath`
    # above).
    #
    # Implemented as a preStart addition on the upstream unit rather than a
    # NixOS activation script: `serviceConfig.User = cfg.user` is already
    # set by the upstream module (nix/nixosModules.nix Mode A), and
    # ExecStartPre/preStart inherit a unit's User=/Group=/hardening by
    # default (no root permission wrapper in play here) -- confirmed no
    # `PermissionsStartOnly`-style override is set anywhere in that file --
    # so this already runs as `${cfg.user}`, matching what a copy into
    # `cfg.stateDir` (already in the unit's `ReadWritePaths`) needs. Native
    # mode (the branch in use here) sets no preStart of its own, so
    # `lib.mkAfter` below is defensive rather than load-bearing -- it keeps
    # this snippet ordered after any preStart upstream might add to Mode A
    # in a future release without needing to revisit this file.
    #
    # Copy-if-absent, mirroring the upstream `authFile` option's own
    # semantics (the non-`authFileForceOverwrite` branch): a token pair
    # already refreshed or self-healed in place must never be clobbered by
    # the sops-managed seed on redeploy.
    #
    # Caveat verified against agent/credential_pool.py and hermes_cli/auth.py
    # at the pinned rev, worth recording since it differs from a naive read
    # of "hermes seeds codex OAuth from ~/.codex/auth.json": Hermes does NOT
    # auto-import this file into its own auth store on a cold start with no
    # prior openai-codex state at all -- `credential_pool.py`'s pool-load
    # code for "openai-codex" explicitly skips it ("we do NOT auto-import
    # from ~/.codex/auth.json at pool-load time"), and
    # `resolve_codex_runtime_credentials()`'s automatic self-heal path only
    # fires once Hermes' own store already holds a *broken* token (error
    # codes for a missing access/refresh token or an invalid shape), not the
    # totally-empty `codex_auth_missing` case a first deploy starts in. So a
    # one-time interactive `hermes auth openai-codex` (accepting the "Import
    # these credentials?" prompt) is still needed after first deploy to
    # actually adopt this seed into Hermes' own store; this preStart's job
    # is only to guarantee that seed file exists and is current for that
    # step, and for the self-heal path to find afterwards once Hermes has a
    # store of its own.
    sops.secrets = {
      # TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, GITHUB_TOKEN --
      # environmentFiles above merges this into $HERMES_HOME/.env at
      # activation. owner/group = the hermes-agent service user (a real
      # static user here, `createUser = true` by default -- not
      # DynamicUser, unlike modules/nixos/attic.nix's atticd -- so a named
      # owner is meaningful and needed for the preStart script above to
      # read the codex-auth.json secret as that same user).
      "hermes/env" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
      };
      # Codex-CLI-format OAuth seed, copied into
      # ${cfg.stateDir}/.codex/auth.json by the preStart script above; see
      # that comment for why this isn't wired through the upstream
      # `authFile` option instead.
      "hermes/codex-auth.json" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
      };
    };

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    systemd = {
      services = {
        hermes-agent = {
          # See the long comment above (before `sops.secrets`) for why this
          # preStart exists and what it does and doesn't guarantee.
          preStart = lib.mkAfter ''
            install -d -m 0700 "${codexAuthDir}"
            if [ ! -f "${codexAuthPath}" ]; then
              install -m 0600 "${config.sops.secrets."hermes/codex-auth.json".path}" "${codexAuthPath}"
            fi
          '';

          # legion-node3 also runs the memory-constrained monitoring stack
          # (modules/nixos/monitoring/default.nix caps VictoriaMetrics at
          # MemoryMax 640M on the same node) -- cap hermes so a runaway
          # agent loop can't starve it. MemoryHigh throttles first (soft
          # cgroup memory pressure, reclaimable); MemoryMax is the hard
          # OOM-kill ceiling.
          serviceConfig = {
            MemoryHigh = "1536M";
            MemoryMax = "2G";
          };
        };

        # Knowledge Base sync (CONTEXT.md "Knowledge Base"): the KB repo
        # remote is the agent's only durable memory. The on-node clone
        # under workingDirectory is Disposable State (CONTEXT.md) -- this
        # timer is what keeps the remote current without relying on the
        # agent remembering to commit/push itself, so knowledge survives a
        # node rebuild (which wipes the clone, `stateDir` carries no
        # Volume/backupSet -- see the module-level comment below on why
        # none is needed) even if the agent never runs `git push` on its
        # own.
        hermes-kb-sync = {
          description = "Sync the Hermes Agent Knowledge Base repo";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          # Separate unit from hermes-agent, so it does not inherit that
          # service's own `path` (built from `extraPackages` above) --
          # git/gh are declared again here for this unit specifically.
          path = [pkgs.git pkgs.gh];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            inherit (cfg) group;
            # GITHUB_TOKEN, read by `gh` below as a non-interactive
            # credential source (gh auto-detects GITHUB_TOKEN/GH_TOKEN
            # from its environment -- no `gh auth login` needed on this
            # box).
            EnvironmentFile = config.sops.secrets."hermes/env".path;
          };
          script = ''
            set -euo pipefail

            KB_DIR="${cfg.workingDirectory}/knowledge-base"

            export GIT_AUTHOR_NAME="Hermes Agent"
            export GIT_AUTHOR_EMAIL="hermes@jeiang.dev"
            export GIT_COMMITTER_NAME="Hermes Agent"
            export GIT_COMMITTER_EMAIL="hermes@jeiang.dev"

            # `-c credential.helper= -c credential.helper='!gh auth git-credential'`:
            # clears any inherited helper, then installs gh's own
            # non-interactive one, which reads GITHUB_TOKEN from the
            # environment above -- no credentials touch disk outside the
            # sops secret itself.
            gitAuth () {
              git -c credential.helper= -c credential.helper='!gh auth git-credential' "$@"
            }

            if [ ! -d "$KB_DIR/.git" ]; then
              gitAuth clone https://github.com/jeiang/knowledge-base.git "$KB_DIR"
              exit 0
            fi

            cd "$KB_DIR"

            # Commit anything the agent left uncommitted before syncing
            # with the remote, so a concurrent agent write is never lost
            # to the rebase/push below.
            git add -A
            if ! git diff --cached --quiet; then
              git commit -m "kb: auto-sync"
            fi

            gitAuth pull --rebase --autostash
            gitAuth push
          '';
        };
      };

      timers.hermes-kb-sync = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnUnitActiveSec = "15m";
          Persistent = true;
        };
      };
    };

    # No firewall openings: Telegram is outbound long-polling, and the
    # Knowledge Base sync/GitHub access above are outbound HTTPS too. No
    # Hetzner Volume, no backupSet: the only durable state is the sops
    # secrets (already backed by the repo's sops workflow) and the KB
    # remote (durable by the timer above); everything under `stateDir` is
    # Disposable State (CONTEXT.md), same reasoning
    # modules/nixos/monitoring/default.nix already documents for its own
    # `stateful = false` inventory entry.
  };
}
