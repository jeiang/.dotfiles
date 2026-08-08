{
  inputs,
  self,
  ...
}: {
  # Hermes Agent (CONTEXT.md "Hermes Agent" -- the personal agent Host-Native
  # Service the fleet runs, consuming the upstream hermes-agent NixOS module
  # directly). Imported only for the inventory node placing `hermes` (piece
  # 4, legion-node3 today, same optional-import pattern as
  # modules/nixos/garret/ / actual-budget.nix in
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

    # hermes-ops SSH client identity (ADR 0012 "Transport" -- the
    # fleet-execution identity, one sops-managed ed25519 key reaching every
    # Legion node's `hermes-ops` account over the Hetzner private network).
    sshDir = "${cfg.stateDir}/.ssh";

    # Host key verification: a repo-wide search (ssh-ed25519/known_hosts/
    # HostKey/ssh_host literals across modules/ and docs/) turns up no
    # committed SSH *host* public keys for any Legion node -- only user/
    # deploy keys (modules/nixos/shared/default.nix's admin key,
    # modules/hosts/legion/default.nix's `legion-deploy` key) and
    # hermes-ops's own *client* key (modules/nixos/hermes-ops/default.nix
    # `authorizedKeys`), none of which is a host key. So ADR 0012
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
    # 0012's "Tier 2 soft enforcement is a residual risk, accepted"
    # section accepts its own gap: the transport rides the Hetzner private
    # network (172.17.0.0/24), not the public internet, so an attacker
    # capable of a first-connection MITM here already has private-network
    # access -- at which point ADR 0012's tier-3 sudo boundary, not
    # host-key pinning, is what actually bounds the damage a compromised
    # session could do. docs/runbooks/hermes.md notes the operator can
    # pre-seed known_hosts on first deploy to skip this TOFU window
    # entirely if they'd rather not accept it.
    sshConfig = pkgs.writeText "hermes-ssh-config" (
      # legion-node3 gets a Host block too (ADR 0012, amended -- this used
      # to be the one node excluded here, running `sudo systemctl ...`
      # directly instead). That local-sudo path can never work: the
      # upstream hermes-agent systemd unit runs NoNewPrivileges=yes
      # (verified via `nix eval
      # .#nixosConfigurations.legion-node3.config.systemd.services.hermes-agent.serviceConfig.NoNewPrivileges`
      # -> true; this module never sets it -- it's upstream's own
      # default). That flag is inherited by every child of the service
      # process and cannot be cleared from within, so no absolute path or
      # sudoers rule lets an in-process `sudo` gain privilege (confirmed
      # live on a deployed node: `NoNewPrivs: 1`, `CapEff:
      # 0000000000000000`, sudo refuses with "The 'no new privileges'
      # flag is set..."). Every privileged fleet action, node3's own
      # included, has to cross an sshd boundary -- a fresh process tree
      # spawned by the TARGET node's sshd, entirely outside this
      # service's sandbox -- to have any chance of landing.
      lib.concatMapStringsSep "\n\n" (node: ''
        Host ${node}
          HostName ${self.lib.legionNodes.${node}.privateIPv4}
          User hermes-ops
          IdentityFile ${sshDir}/id_ed25519
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${sshDir}/known_hosts'')
      ["legion-node1" "legion-node2" "legion-node3" "legion-node4"]
    );

    # iCloud Calendar (feature 8, ADR 0012 credential inventory "iCloud
    # app-specific password for CalDAV"): vdirsyncer mirrors iCloud CalDAV
    # into a local vdir under stateDir, khal reads that vdir. Both
    # packages are added to extraPackages below.
    calendarDir = "${cfg.stateDir}/.vdirsyncer/calendars";
    vdirsyncerStatusDir = "${cfg.stateDir}/.vdirsyncer/status";
    khalConfigDir = "${cfg.stateDir}/.config/khal";

    # Scheduled routines (the `cronjob` tool, SERVERS.md "Cron routines").
    # Upstream stores them as `get_hermes_home()/cron/jobs.json`
    # (`cron/jobs.py` at the pinned rev). `get_hermes_home()` resolves to
    # `${cfg.stateDir}/.hermes` here -- not `cfg.stateDir` itself: the same
    # helper backs `skills_sync.py`'s `SKILLS_DIR = HERMES_HOME /
    # "skills"`, and that directory is observably
    # `/var/lib/hermes/.hermes/skills` on the node, which pins the `.hermes`
    # level. See the preStart symlink below for why this is redirected into
    # the Knowledge Base clone.
    cronStoreDir = "${cfg.stateDir}/.hermes/cron";
    cronStoreTarget = "${cfg.workingDirectory}/knowledge-base/.hermes-cron";

    # vdirsyncer 0.20.0 (the pinned nixpkgs version -- confirmed via `nix
    # eval .#nixosConfigurations.legion-node3.pkgs.vdirsyncer.version`)
    # config format, verified against vdirsyncer's own docs
    # (vdirsyncer.pimutils.org/en/stable/{config,tutorials/icloud}.html): a
    # `[general]`/`[pair]`/`[storage ...]` file, a format unchanged across
    # versions for years. `collections = ["from b"]` (side b only, not
    # `["from a", "from b"]`) deliberately: two-sided discovery is what
    # triggers vdirsyncer's interactive "create this collection on the
    # other side?" prompt, raised when the two independently-discovered
    # lists don't already match -- with only "from b" declared, the local
    # side is never independently discovered, it just mirrors whatever
    # collection names side b (iCloud) reports, so there is nothing to
    # reconcile and nothing to prompt about. This is the same single-sided
    # pattern vdirsyncer's own tutorial uses for a server-authoritative
    # setup. `item_types = ["VEVENT"]` scopes this to calendar events only
    # (khal is a calendar tool; iCloud CalDAV can also carry VTODO, out of
    # scope here).
    #
    # Credentials: `username.fetch`/`password.fetch` with the `"command"`
    # strategy run an argv list (not shell-interpreted) and use its stdout
    # directly -- verified against vdirsyncer's "Storing passwords" docs
    # (vdirsyncer.readthedocs.io/en/stable/keyring.html). `printenv` reads
    # ICLOUD_USERNAME/ICLOUD_APP_PASSWORD from the `hermes-vdirsyncer-sync`
    # unit's EnvironmentFile below (both folded into the existing
    # `hermes/env` sops secret, see that secret's comment) -- no literal
    # credential value is ever written into this Nix-store file, so unlike
    # the SSH key/SOUL.md it needs no preStart copy into stateDir; a plain
    # Nix store path is fine for `VDIRSYNCER_CONFIG` below.
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
      # vdirsyncer's caldav storage does its own CalDAV principal /
      # calendar-home-set discovery (RFC 6764) from this base URL --
      # verified against vdirsyncer's iCloud tutorial, which uses this
      # exact URL with no further well-known configuration needed.
      url = "https://caldav.icloud.com/"
      username.fetch = ["command", "printenv", "ICLOUD_USERNAME"]
      password.fetch = ["command", "printenv", "ICLOUD_APP_PASSWORD"]
      item_types = ["VEVENT"]
    '';

    # khal 0.14.0 (pinned nixpkgs version, same verification method as
    # vdirsyncer above) config, verified against
    # khal.readthedocs.io/en/latest/configure.html. `type = discover` + a
    # glob `path` expands to one khal calendar per vdirsyncer-synced
    # collection directory under calendarDir, so this file doesn't need
    # updating when iCloud calendar names change. `local_timezone` is left
    # unset deliberately: khal falls back to the system timezone when
    # unset (same doc), the right default for a fleet node -- avoids
    # hardcoding a guess at Aidan's timezone here. Unlike vdirsyncer's
    # config, this DOES need a preStart-installed copy (see the preStart
    # comment below): khal has no config-path env var, only its default
    # `$HOME/.config/khal/config` or a `-c` flag, and the agent's own
    # interactive `khal` calls (SOUL.md) use neither.
    khalConfig = pkgs.writeText "hermes-khal-config" ''
      [calendars]
      [[icloud]]
      path = ${calendarDir}/*
      type = discover
    '';
  in {
    imports = [inputs.hermes-agent.nixosModules.default];

    services.hermes-agent = {
      enable = true;

      # sops-fed secrets/env (below) merge into $HERMES_HOME/.env via the
      # upstream activation script -- see the `sops.secrets` block.
      environmentFiles = [config.sops.secrets."hermes/env".path];

      # Non-secret values two Part D integrations need: Actual's
      # private-network URL (feature 3) and Grafana's own loopback URL
      # (feature: Grafana annotations) -- upstream's `environment` option
      # ("Non-secret environment variables... merged into $HERMES_HOME/.env",
      # nix/nixosModules.nix) is the documented home for exactly this, kept
      # separate from the sops-managed `hermes/env` secret because neither
      # value grants access on its own. Actual's port (5006) matches
      # modules/nixos/actual-budget.nix's `services.actual.settings.port`;
      # Grafana's (3000) matches modules/nixos/monitoring/default.nix's
      # `services.grafana.settings.server` (default port, `http_addr
      # "0.0.0.0"`) -- reached over loopback since Grafana runs on this
      # same node (legion-node3).
      environment = {
        ACTUAL_SERVER_URL = "http://172.17.0.4:5006";
        GRAFANA_URL = "http://127.0.0.1:3000";
        # vdirsyncer config path for the agent's own ad-hoc use (SERVERS.md
        # "Calendar"); the dedicated `hermes-vdirsyncer-sync` unit below
        # sets this independently on its own EnvironmentFile-carrying
        # ExecStart.
        VDIRSYNCER_CONFIG = "${vdirsyncerConfig}";
      };

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
          # "max", not "high": the top of the effort scale that actually
          # reaches the wire for this deployment's model. Verified against
          # the pinned rev rather than the config example, which is stale
          # here -- cli-config.yaml.example's `agent.reasoning_effort`
          # comment still lists `"xhigh" (max)` as the ceiling, but
          # hermes_constants.py's `VALID_REASONING_EFFORTS` is
          # ("minimal", "low", "medium", "high", "xhigh", "max", "ultra")
          # and `parse_reasoning_effort` accepts every one of them
          # (anything unrecognized returns None and silently falls back to
          # the default, which is why this needed checking rather than
          # assuming).
          #
          # Not clamped on our path: agent/transports/codex.py builds
          # `_effort_clamp` as {"minimal": "low"}, adds {"ultra": "max"}
          # for gpt-5.6 models (Ultra is the Codex product-tier name; the
          # Responses API wire value is "max"), and only collapses
          # xhigh/max/ultra down to "high" when `is_xai_responses` is set.
          # This deployment is gpt-5.6-luna over openai-codex, not xAI, so
          # "max" passes through unchanged -- and is the same wire value
          # "ultra" would resolve to.
          reasoning_effort = "max";
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

        # artemis LLM provider (feature 7, ADR 0012 "No new credential for
        # the artemis LLM provider"): a named custom provider pointing at
        # llama-swap on artemis (modules/nixos/llama-swap.nix,
        # listenAddress 0.0.0.0:8080, model group "ornith-1.0-9b") over the
        # NetBird mesh. Config schema verified against
        # `cli-config.yaml.example`'s "Named provider overrides" section at
        # the pinned hermes-agent rev (same `gh api
        # repos/NousResearch/hermes-agent/contents/cli-config.yaml.example`
        # discipline as `openai_runtime` above) and against
        # `hermes_cli/config.py` `_normalize_custom_provider_entry` /
        # `providers_dict_to_custom_providers`: a `settings.providers.<name>`
        # entry with a `base_url` becomes a new selectable
        # OpenAI-compatible provider (`--provider artemis` / `/model`),
        # keyed by its own dict key ("artemis") as the provider name;
        # `api_key`/`key_env` are read only if present -- omitting both
        # (as here) means an unauthenticated endpoint, matching mesh
        # membership being the only real gate.
        #
        # Host: the raw NetBird peer IP (100.89.148.91), not the
        # `artemis.jeiang.vpn` mesh DNS name. This provider exists
        # specifically for when things are already degraded (Hermes' own
        # quota exhausted, or bulk/high-volume processing) and embedded
        # NetBird DNS has a history of flakiness on this fleet (see the
        # netbird-dns-config operational note) -- a provider meant to keep
        # working when the mesh is stressed shouldn't add a DNS hop to its
        # own critical path. Tradeoff, accepted: the peer IP isn't
        # guaranteed stable forever (NetBird could reassign it on
        # re-registration) -- if artemis's mesh IP ever changes, update
        # this literal (`netbird status` from any node, or the NetBird
        # dashboard, shows the current one).
        #
        # MANUAL SWITCH ONLY, never automatic: verified against
        # `hermes_cli/fallback_config.py` `get_fallback_chain`, which reads
        # only `config["fallback_providers"]`/`config["fallback_model"]` --
        # entirely separate top-level keys from `providers`, neither of
        # which this module touches, so an entry here can never enter the
        # automatic fallback chain by construction. Selected explicitly at
        # runtime only (SERVERS.md "Alternative model (artemis)").
        #
        # request_timeout_seconds: llama-swap unloads Ornith-1.0-9B after
        # 30 minutes idle (`ttl = 1800`, modules/nixos/llama-swap.nix); the
        # first request after that reload is a cold start and takes far
        # longer than a warm one (the same module's own
        # `healthCheckTimeout = 300` comment already accounts for this on
        # llama-swap's side). Verified this key is read per-provider
        # regardless of built-in vs. custom by
        # `hermes_cli/timeouts.py get_provider_request_timeout`, which
        # indexes `config["providers"][provider_id]["request_timeout_seconds"]`
        # directly off the raw config dict.
        providers.artemis = {
          base_url = "http://100.89.148.91:8080/v1";
          request_timeout_seconds = 600;
        };

        # Alertmanager -> Hermes webhook (proactive alerting: Alertmanager
        # POSTs firing/resolved alert groups here, the agent investigates
        # and reports a diagnosis + recommended action to Telegram
        # unprompted -- it does NOT remediate on its own; see the TOOLSET
        # note below for why and its residual risk). This was the single
        # highest-uncertainty piece of this module -- every claim below is
        # checked against the pinned hermes-agent rev via `gh api`, not
        # assumed:
        #
        # - SAME PROCESS, no new unit/port/MemoryHigh: nix/nixosModules.nix
        #   Mode A (the branch this module already runs -- see the
        #   file-level comment above) execs a single long-running `hermes
        #   gateway` process that serves every `platforms.*.enabled`
        #   adapter concurrently, Telegram included. Enabling
        #   `platforms.webhook` is one more adapter in that same process,
        #   not a new command or systemd unit.
        # - LISTEN ADDRESS: `gateway/platforms/webhook.py`'s `DEFAULT_HOST =
        #   None` comment documents `platforms.webhook.extra.host` as the
        #   pin-to-one-address escape hatch (added for a Fly.io IPv6-only
        #   edge case that doesn't apply here) -- set to "127.0.0.1" below,
        #   so aiohttp binds loopback only. No firewall opening needed:
        #   Alertmanager (modules/nixos/monitoring/default.nix) runs on
        #   this same node and reaches this port over loopback, which
        #   NixOS' firewall never filters regardless of any inbound rule.
        # - AUTH: the same file's request handler permits `secret:
        #   "INSECURE_NO_AUTH"` (skip HMAC validation) ONLY when the
        #   adapter is bound to a loopback host (`_is_loopback_host()`) --
        #   it refuses to start otherwise. That's exactly this setup, so no
        #   HMAC secret / new sops entry is needed here -- and Alertmanager's
        #   standard `webhook_configs` has no built-in way to HMAC-sign its
        #   POST body to this adapter's signature scheme anyway, so a
        #   secret would buy nothing.
        # - ROUTE MECHANISM: the `script` field described in
        #   cli-config.yaml.example's `script_timeout_seconds` comment is
        #   OPTIONAL (a payload transform hook), not the only way to reach
        #   the agent -- a plain route with `prompt` and no `deliver_only`
        #   is enough. `_handle_webhook`'s agent-mode branch renders
        #   `prompt` into a `MessageEvent` and runs it through the SAME
        #   `handle_message()` every other platform uses; the adapter's own
        #   `send()` override then delivers the agent's final response text
        #   to whatever `deliver` names (here "telegram") automatically --
        #   no `send_message` tool call needed on the agent's side. No
        #   route script needed for this route.
        # - TOOLSET: the webhook platform's default toolset
        #   (`hermes-webhook` in toolsets.py, `_HERMES_WEBHOOK_SAFE_TOOLS` =
        #   web_search/web_extract/vision_analyze/clarify only) is
        #   deliberately narrow -- that file's own comment explains why:
        #   webhook payloads can carry untrusted third-party content (a
        #   public GitHub PR title), so the default keeps terminal/file off
        #   to bound prompt-injection blast radius. `platform_toolsets.webhook`
        #   below overrides the default with just `terminal` ("webhook" is
        #   a generic platform key, resolved by the same
        #   `hermes_cli/tools_config.py` `_get_platform_tools()` this
        #   module already relies on for Telegram's default) -- needed for
        #   READ-ONLY investigation: `systemctl status`/`journalctl`, `curl`
        #   to VictoriaLogs/VictoriaMetrics/Grafana, all per SERVERS.md.
        #   None of those reads need sudo or SSH-to-another-node -- node3's
        #   observability stack already centralizes every node's logs and
        #   metrics -- so investigation alone never touches the sudo/SSH
        #   surface at all.
        #
        #   The route's `prompt` (below) explicitly forbids the agent from
        #   taking any action from this turn -- no restart/stop/expose, no
        #   sudo call, even a tier-1-safe one; the agent reports a
        #   diagnosis and a recommended action, and any actual fix happens
        #   only after Aidan approves it in a normal Telegram conversation.
        #   This is a considered, ACCEPTED tradeoff, not an oversight: it is
        #   a PROMPT-LEVEL boundary, not a mechanical one. The `hermes` user
        #   running this turn is the same identity that holds ADR 0012's
        #   hermes-ops SSH access to every node, node3 included (Parts
        #   B/C), and transitively through it every sudo grant on every
        #   node -- `terminal` here is the same tool, so a
        #   sufficiently effective injection via crafted alert label/
        #   annotation content (Alertmanager alert content can originate
        #   from anything that can push a metric or write an alerting
        #   rule -- a lower-trust surface than a human's own Telegram
        #   message) could still get the agent to run a sudo command this
        #   turn, this prompt's "don't act" instruction notwithstanding. A
        #   separate, sudo-less identity for this route was considered and
        #   deliberately not built (Aidan chose this framing over hard
        #   isolation): ADR 0012's sudo allowlist is what actually bounds
        #   the worst case regardless -- every reachable command is still
        #   one from the enumerated tier-1/tier-2 recoverable set, tier 3
        #   has no mechanical path at all -- the same backstop the ADR's
        #   "Tier 2's soft enforcement is a residual risk, accepted"
        #   section already relies on for Telegram-driven tier-2 commands.
        #   See that section (amended) for the full reasoning.
        # - DEPENDENCY: `check_webhook_requirements()` (same file) needs
        #   `aiohttp` importable. It's in hermes-agent's pyproject.toml
        #   `messaging` extra, not the core deps -- but `nix/hermes-agent.nix`
        #   builds this module's package with `dependency-groups = ["all"]
        #   ++ extraDependencyGroups`, and "all" already includes
        #   `messaging` (Telegram already depends on it), so no
        #   `extraDependencyGroups` change is needed here.
        platforms.webhook = {
          enabled = true;
          extra = {
            host = "127.0.0.1";
            # Must match the literal in modules/nixos/monitoring/default.nix's
            # Alertmanager `webhook_configs.url` -- see that file's comment.
            port = 8644;
            routes.alertmanager = {
              # Loopback-only bind (see comment above) -- no HMAC secret needed.
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
        platform_toolsets.webhook = ["terminal"];
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
      # VictoriaMetrics/VictoriaLogs per SERVERS.md, and Grafana annotations
      # (feature: Grafana annotations, SERVERS.md "Grafana annotations").
      # openssh: the `ssh` binary fleet commands run through (ADR 0012
      # "Transport"), using the identity/config the preStart script below
      # installs. khal/vdirsyncer: iCloud Calendar (feature 8) -- vdirsyncer
      # mirrors the CalDAV collection locally (also run by the dedicated
      # `hermes-vdirsyncer-sync` timer below, which declares its own `path`
      # since it's a separate unit), khal is what the agent actually reads
      # and edits events through (SOUL.md, SERVERS.md "Calendar").
      # actual-cli: the `actual` CLI (feature 3, Actual Budget) --
      # `modules/packages/actual-cli.nix`, see that file for why no
      # nixpkgs package exists and how this one is built. Wired onto both
      # the `hermes` user's per-user profile PATH and this service's own
      # systemd PATH (nix/nixosModules.nix `extraPackages` option).
      extraPackages = [
        pkgs.git
        pkgs.gh
        pkgs.curl
        pkgs.openssh
        pkgs.khal
        pkgs.vdirsyncer
        self.packages.${pkgs.stdenv.hostPlatform.system}.actual-cli
      ];
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
      # TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, GITHUB_TOKEN, plus Part
      # D's additions (all folded into this one secret rather than minting
      # separate sops entries -- every one below is a plain string value,
      # not a file, and needs no ownership distinct from this secret's own
      # owner/group; docs/runbooks/hermes.md's credential-inventory section
      # has the exact mint/rotate steps for each):
      #   ACTUAL_SESSION_TOKEN  -- Actual Budget session token (feature 3;
      #     NOT the server login password, see ADR 0012). Invalidated by
      #     Actual's "log out all sessions" action, must be re-minted then.
      #   ACTUAL_SYNC_ID        -- Actual's budget sync ID (Settings ->
      #     Advanced -> Sync ID in the Actual UI). Not itself a credential
      #     (identifies which budget, doesn't authenticate), but
      #     operator-specific and unknown at eval time, so it lives here
      #     next to the token rather than as a Nix-committed literal.
      #   ICLOUD_USERNAME       -- Aidan's iCloud email (feature 8). Same
      #     reasoning as ACTUAL_SYNC_ID: not a secret by itself, but
      #     operator-specific and not something to guess/commit.
      #   ICLOUD_APP_PASSWORD   -- iCloud CalDAV app-specific password
      #     (feature 8, ADR 0012's "unlocks all of Aidan's iCloud
      #     CalDAV/CardDAV" caveat), from appleid.apple.com.
      #   HERMES_REPOS_TOKEN    -- the `hermes-repos` fine-grained GitHub
      #     PAT (feature 9, ADR 0012), distinct from GITHUB_TOKEN's
      #     Knowledge-Base-only scope -- see SOUL.md's "GitHub access"
      #     section and SERVERS.md's "Other Git repos" section for how the
      #     agent picks the right token per repo.
      #   GRAFANA_ANNOTATION_TOKEN -- Grafana service-account token scoped
      #     to annotation writes only (Grafana annotations feature).
      # environmentFiles above merges this into $HERMES_HOME/.env at
      # activation. owner/group = the hermes-agent service user (a real
      # static user here, `createUser = true` by default, not
      # DynamicUser -- so a named owner is meaningful and needed for the preStart script above to
      # read the codex-auth.json secret as that same user).
      #
      # restartUnits: this is read once at agent start-up (merged into
      # $HERMES_HOME/.env at activation), and a deploy that only rotates a
      # token leaves the unit definition byte-identical -- so without it
      # the running agent keeps using the pre-rotation credentials. Only
      # hermes-agent.service: hermes-kb-sync and hermes-vdirsyncer-sync are
      # timer-driven oneshots that read the file fresh on their next run,
      # and listing them here would instead fire a sync on every deploy.
      # See modules/nixos/garret/default.nix for the observed failure.
      "hermes/env" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
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
      # hermes-ops SSH private key (ADR 0012 "Transport"). Installed to
      # `${sshDir}/id_ed25519` by the preStart script below. NOT committed
      # here: the operator adds the key value via `just sops-edit`
      # (docs/runbooks/hermes.md); the matching public half is already
      # committed at modules/nixos/hermes-ops/default.nix's
      # `authorizedKeys`.
      # restartUnits: the preStart installs this unconditionally, so a
      # restart is what actually propagates a rotated key to
      # ${sshDir}/id_ed25519. (`hermes/codex-auth.json` above deliberately
      # gets none: its preStart copy is guarded by `[ ! -f ]`, so a restart
      # would not replace an existing file anyway -- rotating that one is a
      # runbook step, docs/runbooks/hermes.md.)
      "hermes/ssh-key" = {
        inherit sopsFile;
        owner = cfg.user;
        inherit (cfg) group;
        mode = "0400";
        restartUnits = ["hermes-agent.service"];
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

            # hermes-ops SSH identity + config (ADR 0012 "Transport"; see
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

            # khal config (iCloud Calendar, feature 8): unlike
            # vdirsyncer's config (referenced directly from the Nix store
            # via VDIRSYNCER_CONFIG above, no copy needed), khal has no
            # config-path env var -- only its default
            # `$HOME/.config/khal/config` or a `-c` flag -- and the
            # agent's own interactive `khal` calls use neither, so this
            # needs to land at that default path. Overwrite unconditionally,
            # same reasoning as SOUL.md above: nothing on this box ever
            # mutates this file, it is Nix-managed end-to-end.
            install -d -m 0700 "${khalConfigDir}"
            install -m 0640 ${khalConfig} "${khalConfigDir}/config"

            # Cron store into the Knowledge Base clone. Upstream keeps
            # scheduled routines in `cronStoreDir` (see that binding for
            # how the path is derived), which is
            # Disposable State under `stateDir` -- so a node rebuild
            # silently drops every routine the agent was asked to keep.
            # Symlinking that store into the KB clone makes the existing
            # hermes-kb-sync timer (below) push it, and a rebuild restores
            # it with the clone: durability without a Hetzner Volume, which
            # is why `stateful = false` stays correct in
            # modules/hosts/legion/_service-inventory.nix.
            #
            # Dot-prefixed so Obsidian hides it from the vault view -- `git
            # add -A` still picks it up. `cron/output/` (job output, pure
            # churn) is gitignored in the KB repo itself, not excluded
            # here: this is a whole-directory symlink, there is nothing to
            # filter at this end.
            install -d "${cronStoreTarget}"
            # One-time migration off the real directory a pre-symlink
            # deploy left behind. Guarded on `! -L` so this is a no-op on
            # every subsequent start; without it `ln -sfn` onto an existing
            # directory would create the link *inside* it, silently
            # orphaning the routines already there.
            if [ -d "${cronStoreDir}" ] && [ ! -L "${cronStoreDir}" ]; then
              cp -a "${cronStoreDir}/." "${cronStoreTarget}/"
              rm -rf "${cronStoreDir}"
            fi
            ln -sfn "${cronStoreTarget}" "${cronStoreDir}"
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

            # Deliberately NOT `git clone`: hermes-agent's preStart creates
            # `$KB_DIR/.hermes-cron` (the cron store, see that comment) and
            # `git clone` refuses a destination that already exists and is
            # non-empty -- on a fresh node the agent's preStart wins that
            # race whenever it starts before this timer's first run
            # (OnActiveSec=1m below). init+fetch+checkout is the same end
            # state and tolerates a pre-populated directory; `checkout -f`
            # is what lets a tracked path land on top of one the preStart
            # already created. Idempotent, so a half-finished previous run
            # (network drop between init and checkout) heals on the next
            # tick rather than wedging on a `.git` that exists but has no
            # commits.
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

        # iCloud Calendar sync (feature 8): mirrors the same
        # timer-plus-on-demand shape as hermes-kb-sync above, for the same
        # reason -- the local vdir under stateDir is Disposable State
        # (CONTEXT.md), re-populated from iCloud on every run, so unlike
        # the Knowledge Base there is nothing here to back up; this timer
        # exists purely to keep the local copy current, not to make it
        # durable.
        hermes-vdirsyncer-sync = {
          description = "Sync Hermes' iCloud calendar via vdirsyncer";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          # Separate unit from hermes-agent, so it does not inherit that
          # service's own `path` -- vdirsyncer is declared again here.
          path = [pkgs.vdirsyncer];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            # ICLOUD_USERNAME, ICLOUD_APP_PASSWORD -- read by vdirsyncer's
            # `username.fetch`/`password.fetch` `printenv` commands (see
            # the `vdirsyncerConfig` comment above).
            EnvironmentFile = config.sops.secrets."hermes/env".path;
            Environment = "VDIRSYNCER_CONFIG=${vdirsyncerConfig}";
          };
          script = ''
            set -euo pipefail

            # vdirsyncer's filesystem storage needs its `path` to already
            # exist; status_path is where sync-state metadata lives.
            # Both under stateDir -- see the module-level Disposable State
            # comment below.
            install -d -m 0700 "${calendarDir}" "${vdirsyncerStatusDir}"

            # `discover` is safe to re-run every time -- cheap, and picks
            # up any calendar iCloud-side renames/adds without a separate
            # one-time setup step.
            #
            # The `y` feed is what makes it non-interactive. `collections =
            # ["from b"]` (see `vdirsyncerConfig` above) decides which side
            # is authoritative, NOT whether discovery prompts: for every
            # remote collection with no local counterpart, vdirsyncer asks
            # `Should vdirsyncer attempt to create it? [y/N]` and reads the
            # answer from stdin, which a systemd oneshot doesn't have -- so
            # the first run after auth started working failed on the prompt
            # rather than on the sync. `discover` has no `--yes` (only
            # `--list`, verified against vdirsyncer 0.20.0's `discover
            # --help`), so stdin is the only lever. Answering `y` is the
            # right answer here and not a rubber stamp: the local vdir is
            # Disposable State, mirrored from iCloud, so creating it is
            # exactly the intent -- there is no local-only calendar that a
            # `y` could clobber.
            #
            # A bounded feed rather than `yes |`: under `pipefail` a `yes`
            # killed by SIGPIPE when vdirsyncer exits first would fail the
            # unit. 100 `y` lines is ~200 bytes, well inside the pipe
            # buffer, so printf always completes and exits 0 regardless of
            # how many prompts vdirsyncer actually consumes.
            printf 'y\n%.0s' $(seq 1 100) | vdirsyncer discover icloud_calendar
            vdirsyncer sync icloud_calendar
          '';
        };
      };

      timers = {
        hermes-kb-sync = {
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

        # Same OnActiveSec/OnUnitActiveSec reasoning as hermes-kb-sync
        # above; ~15m cadence per the plan for this integration.
        hermes-vdirsyncer-sync = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnActiveSec = "1m";
            OnUnitActiveSec = "15m";
          };
        };
      };
    };

    # No firewall openings: Telegram is outbound long-polling, the
    # Knowledge Base sync/GitHub access above are outbound HTTPS, and the
    # hermes-ops SSH transport (ADR 0012 "Transport") is outbound-only too
    # -- Hermes dials out to 172.17.0.{1,2,4}, nothing dials in here. Part
    # D's integrations are the same shape: Actual (172.17.0.4:5006) and
    # Grafana (127.0.0.1:3000) are private-network/loopback outbound calls
    # to services this fleet already runs; vdirsyncer's iCloud sync is
    # outbound HTTPS to caldav.icloud.com; the artemis provider is an
    # outbound call over the NetBird mesh, which -- like the KB
    # sync/GitHub access -- needs no firewall opening on this node (NixOS'
    # firewall only filters inbound by default). The Alertmanager webhook
    # (`platforms.webhook` above) is the one INBOUND listener this module
    # adds, and it needs no opening either: it's bound to 127.0.0.1 only
    # (`extra.host`), reached exclusively by Alertmanager on this same
    # node, and loopback traffic bypasses the firewall's inbound filtering
    # entirely regardless of any rule. No Hetzner Volume, no
    # backupSet: the only durable state is the sops secrets (already backed
    # by the repo's sops workflow) and the KB remote (durable by the timer
    # above); everything under `stateDir` is Disposable State
    # (CONTEXT.md) -- including the cron store, which is only nominally
    # under `stateDir`: the preStart symlinks it into the KB clone
    # (`cronStoreTarget`), so its durable copy is the KB remote like
    # everything else here, not a Volume -- and including the calendar
    # vdir Part D adds, which
    # re-syncs from iCloud on the next `hermes-vdirsyncer-sync` run, so it
    # needs no backup either -- same reasoning
    # modules/nixos/monitoring/default.nix already documents for its own
    # `stateful = false` inventory entry.
  };
}
