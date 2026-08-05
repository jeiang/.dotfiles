{
  inputs,
  self,
  ...
}: {
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
    sopsFile = ./secrets.yaml;

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

    # hermes-ops SSH client identity (ADR 0011 "Transport" -- the
    # fleet-execution identity, one sops-managed ed25519 key reaching every
    # Legion node's `hermes-ops` account over the Hetzner private network).
    sshDir = "${cfg.stateDir}/.ssh";

    # Host key verification: a repo-wide search (ssh-ed25519/known_hosts/
    # HostKey/ssh_host literals across modules/ and docs/) turns up no
    # committed SSH *host* public keys for any Legion node -- only user/
    # deploy keys (modules/nixos/shared/default.nix's admin key,
    # modules/hosts/legion/default.nix's `legion-deploy` key) and
    # hermes-ops's own *client* key (modules/nixos/hermes-ops/default.nix
    # `authorizedKeys`), none of which is a host key. So ADR 0011
    # Transport's alternative (a) -- a Nix-managed known_hosts pinned to
    # real host keys -- isn't available offline here.
    #
    # This uses alternative (b) instead: `StrictHostKeyChecking accept-new`
    # (trust-on-first-connect; a *changed* key after that is still
    # rejected) against a persistent `${sshDir}/known_hosts` under
    # stateDir. Deliberately NOT `StrictHostKeyChecking no`, which accepts
    # every connection unconditionally forever and would open a standing
    # MITM window with no verification at all, first connection or
    # hundredth. accept-new's residual risk -- a MITM on the very first
    # connection to a given node -- is accepted for the same reason ADR
    # 0011's "Tier 2 soft enforcement is a residual risk, accepted"
    # section accepts its own gap: the transport rides the Hetzner private
    # network (172.17.0.0/24), not the public internet, so an attacker
    # capable of a first-connection MITM here already has private-network
    # access -- at which point ADR 0011's tier-3 doas boundary, not
    # host-key pinning, is what actually bounds the damage a compromised
    # session could do. docs/runbooks/hermes.md notes the operator can
    # pre-seed known_hosts on first deploy to skip this TOFU window
    # entirely if they'd rather not accept it.
    sshConfig = pkgs.writeText "hermes-ssh-config" (
      # No Host block for legion-node3: it's this service's own node, so
      # fleet actions there run `doas systemctl ...` directly
      # (hermesOps.extraGrantees, ADR 0011 "node-local actions use doas
      # directly without SSH-to-self") -- there is nothing for SSH to
      # reach.
      lib.concatMapStringsSep "\n\n" (node: ''
        Host ${node}
          HostName ${self.lib.legionNodes.${node}.privateIPv4}
          User hermes-ops
          IdentityFile ${sshDir}/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${sshDir}/known_hosts'')
      ["legion-node1" "legion-node2" "legion-node4"]
    );
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
        agent = {
          reasoning_effort = "high";
          # OpenAI Priority Processing ("fast mode"). The gateway maps
          # "fast" -> service_tier=priority (gateway/run.py
          # `_load_service_tier` at the pinned rev), and gpt-5.6-luna is
          # fast-eligible (hermes_cli/models.py `_is_openai_fast_model`:
          # gpt-* prefix, non-codex). Declared here so every activation
          # re-asserts it over any `/fast --global` runtime toggle, same
          # reasoning as `openai_runtime` above.
          service_tier = "fast";
        };

        # cli-config.yaml.example at the pinned rev (fetched via `gh api
        # repos/NousResearch/hermes-agent/contents/cli-config.yaml.example`,
        # ref v2026.7.30 -- same discipline as `openai_runtime` above)
        # confirms `memory.nudge_interval` (default already 10 upstream,
        # but declared here so an operator's runtime `/memory` toggle can't
        # silently outlive a redeploy, same reasoning as `openai_runtime`)
        # and that `memory_enabled`/`user_profile_enabled` both default to
        # `true` -- left undeclared since there is nothing to pin them
        # against yet.
        memory.nudge_interval = 10;

        # `skills.external_dirs` (same example file, same rev): a list of
        # paths, each `~`/`${VAR}`-expanded and resolved absolute,
        # read-only skill sources layered under the agent's own writable
        # `~/.hermes/skills/`. Points at the Knowledge Base clone's
        # `skills/` (see SOUL.md's knowledge-discipline section) so
        # self-created skills Hermes persists there are loadable back in as
        # skills, not just backed-up files. `agent/skill_utils.py
        # get_external_skills_dirs()` at the pinned rev silently drops any
        # entry that doesn't exist on disk yet (no error, no crash) --
        # confirmed there, so a fresh `hermes-kb-sync` clone that hasn't
        # created `knowledge-base/skills/` yet is not a problem this
        # module's preStart needs to `install -d` around.
        skills.external_dirs = ["${cfg.workingDirectory}/knowledge-base/skills"];
      };

      # SERVERS.md is colocated with this module (documents values may be
      # paths -- nix/nixosModules.nix `documentDerivation`) and gets
      # installed fresh into workingDirectory on EVERY activation, so
      # in-place self-edits by the agent never persist.
      #
      # SOUL.md is NOT wired through `documents`: that option only drops
      # files into workingDirectory, but the runtime loads its persona from
      # `$HERMES_HOME/SOUL.md` = `${cfg.stateDir}/.hermes/SOUL.md`
      # (agent/prompt_builder.py `load_soul_md()` at the pinned rev) and
      # seeds DEFAULT_SOUL_MD there on first run -- a SOUL.md in the
      # workspace is inert. Ours is installed to the real path by the
      # preStart script below.
      documents = {
        "SERVERS.md" = ./SERVERS.md;
      };

      # git/gh: the agent's own terminal tool needs them for GitHub access
      # and for the Knowledge Base repo (also used by hermes-kb-sync below,
      # which needs its own explicit `path` since it's a separate systemd
      # unit and doesn't inherit this list). curl: querying
      # VictoriaMetrics/VictoriaLogs per SERVERS.md. openssh: the `ssh`
      # binary fleet commands run through (ADR 0011 "Transport"), using the
      # identity/config the preStart script below installs. Wired onto both
      # the `hermes` user's per-user profile PATH and this service's own
      # systemd PATH (nix/nixosModules.nix `extraPackages` option).
      extraPackages = [pkgs.git pkgs.gh pkgs.curl pkgs.openssh];
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
    # totally-empty `codex_auth_missing` case a first deploy starts in. Nor
    # does `hermes auth add openai-codex` import it -- that goes straight to
    # a fresh device-code login (the interactive "Import these credentials?"
    # adoption prompt exists only for the Nous provider on this rev). So the
    # one-time interactive `hermes auth add openai-codex` device flow is
    # required after first deploy (docs/runbooks/hermes.md); this seed's
    # only remaining job is the malformed-store self-heal case, and only
    # while its sops copy holds unexpired tokens.
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
      # hermes-ops SSH private key (ADR 0011 "Transport"). Installed to
      # `${sshDir}/id_ed25519` by the preStart script below. NOT committed
      # here: the operator adds the key value via `just sops-edit`
      # (docs/runbooks/hermes.md); the matching public half is already
      # committed at modules/nixos/hermes-ops/default.nix's
      # `authorizedKeys`.
      "hermes/ssh-key" = {
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

            # Persona: overwrite unconditionally (Nix-managed, see the note
            # at the top of SOUL.md) at the path the runtime actually reads
            # -- see the `documents` comment above for why this can't go
            # through that option.
            install -m 0640 ${./SOUL.md} "${cfg.stateDir}/.hermes/SOUL.md"

            # hermes-ops SSH identity + config (ADR 0011 "Transport"; see
            # the `sshDir`/`sshConfig` comments above for what these are
            # and the host-key-verification tradeoff).
            install -d -m 0700 "${sshDir}"

            # Always overwrite -- unlike codex-auth.json's copy-if-absent
            # above. That file self-heals in place (Hermes' own OAuth
            # refresh writes back to it), so clobbering it on every restart
            # would lose a live token. This key does not: nothing on this
            # box ever mutates it, it is Nix/sops-managed end-to-end, so
            # "copy if absent" would instead mean a rotated sops key never
            # propagates to a running deploy -- the old (possibly revoked)
            # key would keep authenticating until someone noticed and
            # manually intervened. Overwriting every start makes key
            # rotation take effect on the very next deploy, matching how
            # every other Nix-managed file in this preStart already
            # behaves (SOUL.md above, the SSH config below).
            install -m 0600 "${config.sops.secrets."hermes/ssh-key".path}" "${sshDir}/id_ed25519"
            install -m 0600 ${sshConfig} "${sshDir}/config"
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
            Group = cfg.group;
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
          # OnUnitActiveSec alone never fires on a service that has never
          # been active (there is no "last activation" to be relative to),
          # so the sync -- including the initial clone -- would never run.
          # OnActiveSec schedules the first run relative to the timer's own
          # activation (every boot, and any deploy that restarts the timer);
          # OnUnitActiveSec keeps the 15m cadence after that. Persistent=
          # was dropped: it only applies to OnCalendar= timers.
          OnActiveSec = "1m";
          OnUnitActiveSec = "15m";
        };
      };
    };

    # No firewall openings: Telegram is outbound long-polling, the
    # Knowledge Base sync/GitHub access above are outbound HTTPS, and the
    # hermes-ops SSH transport (ADR 0011 "Transport") is outbound-only too
    # -- Hermes dials out to 172.17.0.{1,2,4}, nothing dials in here. No
    # Hetzner Volume, no backupSet: the only durable state is the sops
    # secrets (already backed by the repo's sops workflow) and the KB
    # remote (durable by the timer above); everything under `stateDir` is
    # Disposable State (CONTEXT.md), same reasoning
    # modules/nixos/monitoring/default.nix already documents for its own
    # `stateful = false` inventory entry.
  };
}
