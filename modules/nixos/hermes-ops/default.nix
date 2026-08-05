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
  # The sudo allowlist below IS the Fleet Operations Tiers classifier
  # (docs/adr/0012-extend-the-scoped-credential-agent-into-a-tiered-fleet-operator.md
  # "Why the sudo allowlist is the classifier"): tier 1 (free) and tier 2
  # (soft-confirm) units get MECHANICALLY IDENTICAL sudo rules --
  # `systemctl start`/`restart` on the unit -- because the tier split is a
  # SOUL.md/prompt-level convention Hermes itself enforces before running a
  # tier-2 command, not something sudo can see or gate. `systemctl stop` is
  # generated for every unit in both lists (ADR 0012 tier 2: stop is always
  # tier-2 behavior, mechanically no different from a restart). Tier 3 is
  # the ABSENCE of a rule: nothing here ever names sshd, netbird
  # up/down/login, nixos-rebuild, or hermes-agent itself -- there is no
  # line to point to for "why is X forbidden", which is the point.
  #
  # sudo, not doas: Legion enables `security.sudo` fleet-wide (the nixpkgs
  # default) and never imports `flake.nixosModules.doas`
  # (modules/nixos/security.nix), which is artemis-only and disables sudo
  # where it IS imported. A doas allowlist here would evaluate but never
  # run -- no doas binary would exist on any Legion node. Don't
  # re-introduce a doas rule for this module without also importing that
  # module fleet-wide, which was rejected (a second privilege-escalation
  # path and a new setuid binary on 4 production nodes for one consumer).
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
    # ADR 0012 "node-local actions use sudo directly without
    # SSH-to-self") -- all commands are granted through a single sudo
    # rule's `users` list, so this doesn't double the rule count per
    # extra grantee.
    grantees = ["hermes-ops"] ++ cfg.extraGrantees;

    # ADR 0012 "verb-times-unit enumerations, no wildcards": a
    # security.sudo.extraRules `commands[].command` string is matched
    # against the invoked command line LITERALLY, arguments included --
    # verified against the pinned nixpkgs
    # nixos/modules/security/sudo.nix (`toCommandsString`/`toCommandOptionsString`
    # concatenate `command.options` and `command.command` into the
    # sudoers line with no glob/prefix expansion of their own), so one
    # command entry per (verb, unit) is the only way to permit exactly
    # this unit at this verb without also permitting an unlisted one.
    mkSystemctlCommand = verb: unit: {
      command = "${systemctlPath} ${verb} ${unit}";
      options = ["NOPASSWD"]; # hermes-ops has no password; tier 2's confirm gate is prompt-level (ADR 0012).
    };

    startRestartCommands =
      lib.concatMap (unit: [(mkSystemctlCommand "start" unit) (mkSystemctlCommand "restart" unit)])
      (cfg.tier1Units ++ cfg.tier2Units);
    # De-duplicated: a unit present in both lists (none today, but the
    # option shape allows it) would otherwise get two identical stop
    # command entries.
    stopCommands = map (mkSystemctlCommand "stop") (lib.unique (cfg.tier1Units ++ cfg.tier2Units));

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
    # capability stays sudo-mediated (root bypasses the group check same
    # as any other file permission), so this needs a sudo rule exactly
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
    # (unlike expose below) there's nothing that needs to stay
    # unconstrained -- this is a plain literal-command entry like the
    # systemctl ones above.
    netbirdStatusCommand = {
      command = "${netbirdBin} status";
      options = ["NOPASSWD"];
    };

    # Tier 2: `netbird expose <port> [flags]` (ADR 0012 "the netbird
    # expose subcommand family" -- verified present as a single top-level
    # cobra command, no sub-subcommands, in the pinned netbird v0.76.1
    # source, modules/packages/netbird.nix). The port/flags are
    # caller-chosen, so a literal `command` string can't enumerate every
    # valid invocation the way the systemctl rules above do, and sudoers
    # has no prefix/glob form for arguments -- granting a bare command
    # path (no arguments appended, per the pinned nixpkgs
    # security.sudo.extraRules `commands[].command` option doc: "just a
    # path to a binary" permits any arguments, the equivalent of doas'
    # `args = null`) directly on the netbird binary would permit ANY
    # argument to it, silently reopening `netbird up`/`down`/`login`
    # (tier 3, must stay forbidden) through the same rule. The fix is a
    # single-purpose wrapper that can only ever exec `netbird expose
    # "$@"`: sudo grants unconstrained args to the WRAPPER, not to the
    # real netbird binary, so the command surface this rule opens stays
    # hard-locked to `expose` no matter what arguments are passed.
    netbirdExposeWrapper = pkgs.writeShellApplication {
      name = "hermes-ops-netbird-expose";
      text = ''exec ${netbirdBin} expose "$@"'';
    };
    netbirdExposeCommand = {
      command = lib.getExe netbirdExposeWrapper; # no arguments appended -- permits any, see above
      options = ["NOPASSWD"];
    };
  in {
    options.hermesOps = {
      tier1Units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          This node's tier-1 (free) systemd unit names. `systemctl
          start`/`restart` on these needs no Telegram confirmation (ADR
          0012). Set per-node by modules/hosts/legion/default.nix, not by
          hand elsewhere.
        '';
      };
      tier2Units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          This node's tier-2 (soft-confirm) systemd unit names. Sudo
          rules identical to tier 1 -- the confirmation gate is a
          SOUL.md/prompt-level convention, not a mechanical one (ADR
          0012). Set per-node by modules/hosts/legion/default.nix, not by
          hand elsewhere.
        '';
      };
      extraGrantees = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Extra usernames (besides hermes-ops) to grant this node's sudo
          rules and systemd-journal membership to. legion-node3 sets this
          to the hermes-agent service user (ADR 0012: node-local actions
          use sudo directly, without SSH-to-self) from its own host
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
              # systemd-journal: the journalctl-fallback read path (ADR 0012
              # tier 1: direct journalctl on the node when VictoriaLogs is
              # unreachable). No other group -- every other hermes-ops
              # capability is mechanical, through the sudo rules below,
              # never through Unix group membership (see the netbird
              # comment above for why that applies there too).
              extraGroups = ["systemd-journal"];
              openssh.authorizedKeys.keys = [
                # from=: SSH to hermes-ops only ever originates from
                # legion-node3, where Hermes lives (ADR 0012 "Transport") --
                # every other source IP is rejected at the key level,
                # before sudo or any command runs.
                # no-agent-forwarding/no-X11-forwarding: this account has
                # no business relaying either. Deliberately NO forced
                # `command=`: ADR 0012's transport section is explicit that
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
          # journal-read fallback as hermes-ops; their sudo access comes
          # from `grantees` above, not from group membership.
          // lib.genAttrs cfg.extraGrantees (_: {extraGroups = ["systemd-journal"];});
      };

      # A single rule covering every grantee, all commands enumerated in
      # its `commands` list -- not `security.sudo.enable` (already true
      # fleet-wide via the base config, untouched here) and not
      # `wheelNeedsPassword`/any other global sudo setting, only this
      # `extraRules` append.
      security.sudo.extraRules = [
        {
          users = grantees;
          commands = startRestartCommands ++ stopCommands ++ [netbirdStatusCommand netbirdExposeCommand];
        }
      ];

      # No firewall change: modules/hosts/legion/default.nix already trusts
      # enp7s0 (networking.firewall.trustedInterfaces), the Hetzner private
      # network hermes-ops's SSH transport rides (172.17.0.0/24) -- inbound
      # SSH from 172.17.0.3 is already reachable on every Legion node
      # without any opening here.
    };
  };
}
