_: {
  # hermes-ops (CONTEXT.md "hermes-ops"): the Hermes Agent's unprivileged
  # fleet-execution identity, present on every Legion node. Imported
  # fleet-wide and unconditionally by
  # modules/hosts/legion/default.nix's legionConfiguration, the same
  # pattern as self.nixosModules.netbird/backups -- this is cross-cutting
  # fleet policy (every node needs it, regardless of which services it
  # places), not a placed service, so it carries no
  # modules/hosts/legion/_service-inventory.nix entry.
  #
  # The doas allowlist below IS the Fleet Operations Tiers classifier
  # (docs/adr/0011-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md
  # "Why the doas allowlist is the classifier"): tier 1 (free) and tier 2
  # (soft-confirm) units get MECHANICALLY IDENTICAL doas rules --
  # `systemctl start`/`restart` on the unit -- because the tier split is a
  # SOUL.md/prompt-level convention Hermes itself enforces before running a
  # tier-2 command, not something doas can see or gate. `systemctl stop` is
  # generated for every unit in both lists (ADR 0011 tier 2: stop is always
  # tier-2 behavior, mechanically no different from a restart). Tier 3 is
  # the ABSENCE of a rule: nothing here ever names sshd, netbird
  # up/down/login, nixos-rebuild, or hermes-agent itself -- there is no
  # line to point to for "why is X forbidden", which is the point.
  flake.nixosModules.hermes-ops = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.hermesOps;

    systemctlPath = "/run/current-system/sw/bin/systemctl";

    # Every rule below is granted to hermes-ops itself plus this node's
    # extra grantees (legion-node3 only: the hermes-agent service user,
    # ADR 0011 "node-local actions use doas directly without
    # SSH-to-self") -- one rule per (verb, unit) pair covers every
    # grantee via doas' own multi-user `users` list, so this doesn't
    # double the rule count per extra grantee.
    grantees = ["hermes-ops"] ++ cfg.extraGrantees;

    # ADR 0011 "verb-times-unit enumerations, no wildcards": doas.conf(5)
    # `args` matching is exact-literal only (no glob/prefix form), so one
    # rule per (verb, unit) is the only way to permit exactly this unit at
    # this verb without also permitting an unlisted one.
    mkSystemctlRule = verb: unit: {
      users = grantees;
      cmd = systemctlPath;
      args = [verb unit];
      noPass = true; # hermes-ops has no password; tier 2's confirm gate is prompt-level (ADR 0011).
    };

    startRestartRules =
      lib.concatMap (unit: [(mkSystemctlRule "start" unit) (mkSystemctlRule "restart" unit)])
      (cfg.tier1Units ++ cfg.tier2Units);
    # De-duplicated: a unit present in both lists (none today, but the
    # option shape allows it) would otherwise get two identical stop
    # rules.
    stopRules = map (mkSystemctlRule "stop") (lib.unique (cfg.tier1Units ++ cfg.tier2Units));

    # config.services.netbird.clients.default is defined by
    # self.nixosModules.netbird (modules/nixos/netbird.nix), imported
    # fleet-wide and unconditionally alongside this module in
    # modules/hosts/legion/default.nix's legionConfiguration -- so, unlike
    # cfg.extraGrantees' hermes-agent reference (kept out of this module
    # entirely, see the option doc below), referencing it here doesn't
    # make this module usable only when some *optional* per-node service
    # happens to be placed. Same cross-module reference style
    # modules/nixos/blocky.nix already uses
    # (config.services.netbird.clients.default.service.name).
    #
    # That module sets no `hardened` override, so the client stays at the
    # nixpkgs default (`hardened = true`): the daemon runs as a dedicated
    # `netbird-default` user/group, not root, and its control socket's
    # RuntimeDirectoryMode (0750) is unreadable/unwritable to anyone
    # outside that user/group (verified against the pinned nixpkgs
    # rev's nixos/modules/services/networking/netbird.nix hardening
    # section). hermes-ops is not added to that group -- every hermes-ops
    # capability stays doas-mediated (root bypasses the group check same
    # as any other file permission), so this needs a doas rule exactly
    # like the systemctl ones above, not a group grant.
    #
    # `wrapper`, not the bare package, is required: the wrapper is what
    # bakes in `--set-default NB_DAEMON_ADDR unix:///var/run/netbird-default/sock`
    # via makeWrapperArgs (nixpkgs netbird.nix `client.wrapper`) -- the raw
    # binary's own compiled-in default (patched in
    # modules/packages/netbird.nix to /var/run/netbird/sock) is for the
    # unsuffixed single-client case and does NOT match this fleet's
    # "default"-named client's actual runtime directory
    # (/var/run/netbird-default), so calling it unwrapped would connect to
    # the wrong (nonexistent) socket.
    netbirdBin = lib.getExe config.services.netbird.clients.default.wrapper;

    # Tier 1: read-only status. Takes no mandatory positional argument, so
    # (unlike expose below) there's nothing that needs a wildcard --
    # this is a plain literal-args rule like the systemctl ones above.
    netbirdStatusRule = {
      users = grantees;
      cmd = netbirdBin;
      args = ["status"];
      noPass = true;
    };

    # Tier 2: `netbird expose <port> [flags]` (ADR 0011 "the netbird
    # expose subcommand family" -- verified present as a single top-level
    # cobra command, no sub-subcommands, in the pinned netbird v0.76.1
    # source, modules/packages/netbird.nix). The port/flags are
    # caller-chosen, so doas' literal-args matching can't enumerate every
    # valid invocation the way the systemctl rules above do, and
    # doas.conf(5) has no prefix/glob form for `args` -- granting `args =
    # null` (no `args` keyword at all) directly on the netbird binary
    # would permit ANY argument to it, silently reopening `netbird
    # up`/`down`/`login` (tier 3, must stay forbidden) through the same
    # rule. The fix is a single-purpose wrapper that can only ever exec
    # `netbird expose "$@"`: doas grants unconstrained args to the
    # WRAPPER, not to the real netbird binary, so the command surface
    # this rule opens stays hard-locked to `expose` no matter what
    # arguments are passed.
    netbirdExposeWrapper = pkgs.writeShellApplication {
      name = "hermes-ops-netbird-expose";
      text = ''exec ${netbirdBin} expose "$@"'';
    };
    netbirdExposeRule = {
      users = grantees;
      cmd = lib.getExe netbirdExposeWrapper;
      args = null;
      noPass = true;
    };
  in {
    options.hermesOps = {
      tier1Units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          This node's tier-1 (free) systemd unit names. `systemctl
          start`/`restart` on these needs no Telegram confirmation (ADR
          0011). Set per-node by modules/hosts/legion/default.nix, not by
          hand elsewhere.
        '';
      };
      tier2Units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          This node's tier-2 (soft-confirm) systemd unit names. Doas
          rules identical to tier 1 -- the confirmation gate is a
          SOUL.md/prompt-level convention, not a mechanical one (ADR
          0011). Set per-node by modules/hosts/legion/default.nix, not by
          hand elsewhere.
        '';
      };
      extraGrantees = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Extra usernames (besides hermes-ops) to grant this node's doas
          rules and systemd-journal membership to. legion-node3 sets this
          to the hermes-agent service user (ADR 0011: node-local actions
          use doas directly, without SSH-to-self) from its own host
          config, so this module never references
          config.services.hermes-agent itself and has no hard dependency
          on modules/nixos/hermes/default.nix being imported.
        '';
      };
    };

    # All `users.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across
    # separate top-level entries works fine in Nix, but is flagged as a
    # style issue).
    config = {
      users = {
        groups.hermes-ops = {};
        users =
          {
            hermes-ops = {
              isSystemUser = true;
              group = "hermes-ops";
              home = "/var/empty";
              createHome = false;
              hashedPassword = "!";
              shell = pkgs.bashInteractive;
              # systemd-journal: the journalctl-fallback read path (ADR 0011
              # tier 1: direct journalctl on the node when VictoriaLogs is
              # unreachable). No other group -- every other hermes-ops
              # capability is mechanical, through the doas rules below,
              # never through Unix group membership (see the netbird
              # comment above for why that applies there too).
              extraGroups = ["systemd-journal"];
              openssh.authorizedKeys.keys = [
                # from=: SSH to hermes-ops only ever originates from
                # legion-node3, where Hermes lives (ADR 0011 "Transport") --
                # every other source IP is rejected at the key level,
                # before doas or any command runs.
                # no-agent-forwarding/no-X11-forwarding: this account has
                # no business relaying either. Deliberately NO forced
                # `command=`: ADR 0011's transport section is explicit that
                # this is general command execution as hermes-ops, not one
                # fixed command -- a forced command would defeat that.
                #
                # Public half only; the private half is sops-managed and
                # wired in at the credential-inventory checkpoint
                # (docs/runbooks/hermes.md), not committed here.
                ''from="172.17.0.3",no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvcTYBeAVez+6x8r4gCOR6eIjBE0oPSYOsW3Qj4znjE hermes-ops fleet key''
              ];
            };
          }
          # Extra grantees (legion-node3's hermes-agent user) get the same
          # journal-read fallback as hermes-ops; their doas access comes
          # from `grantees` above, not from group membership.
          // lib.genAttrs cfg.extraGrantees (_: {extraGroups = ["systemd-journal"];});
      };

      security.doas.extraRules = startRestartRules ++ stopRules ++ [netbirdStatusRule netbirdExposeRule];

      # No firewall change: modules/hosts/legion/default.nix already trusts
      # enp7s0 (networking.firewall.trustedInterfaces), the Hetzner private
      # network hermes-ops's SSH transport rides (172.17.0.0/24) -- inbound
      # SSH from 172.17.0.3 is already reachable on every Legion node
      # without any opening here.
    };
  };
}
