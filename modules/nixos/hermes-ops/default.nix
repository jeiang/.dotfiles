_: {
  flake.nixosModules.hermes-ops = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.hermesOps;

    systemctlPath = "/run/current-system/sw/bin/systemctl";

    # sudoers matches the invoked command line literally, arguments included
    # -- one entry per (verb, unit) is the only way to permit exactly that.
    mkSystemctlCommand = verb: unit: {
      command = "${systemctlPath} ${verb} ${unit}";
      options = ["NOPASSWD"];
    };

    startRestartCommands =
      lib.concatMap (unit: [(mkSystemctlCommand "start" unit) (mkSystemctlCommand "restart" unit)])
      (cfg.tier1Units ++ cfg.tier2Units);
    stopCommands = map (mkSystemctlCommand "stop") (lib.unique (cfg.tier1Units ++ cfg.tier2Units));

    # `wrapper`, not the bare package: the wrapper bakes in the "default"
    # client's NB_DAEMON_ADDR; the raw binary points at the wrong socket.
    netbirdBin = lib.getExe config.services.netbird.clients.default.wrapper;

    netbirdStatusCommand = {
      command = "${netbirdBin} status";
      options = ["NOPASSWD"];
    };

    # A bare command path in sudoers permits ANY arguments, which would
    # silently reopen `netbird up`/`down`/`login` (tier 3, forbidden); the
    # wrapper hard-locks the grant's command surface to `expose`.
    netbirdExposeWrapper = pkgs.writeShellApplication {
      name = "hermes-ops-netbird-expose";
      text = ''exec ${netbirdBin} expose "$@"'';
    };
    netbirdExposeCommand = {
      command = lib.getExe netbirdExposeWrapper;
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
      journalGrantees = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Extra usernames (besides hermes-ops) added to systemd-journal on
          this node, for local `journalctl` reads with no SSH hop needed.
          legion-node3 sets this to the hermes-agent service user, from
          its own host config, so this module never references
          config.services.hermes-agent itself and has no hard dependency
          on modules/nixos/hermes/default.nix being imported. Grants NO
          sudo access (that was removed, ADR 0012 amended): the
          hermes-agent unit runs NoNewPrivileges=yes (upstream-set), which
          blocks in-process privilege escalation entirely, so a sudo grant
          to that user could never be exercised. Reading the journal needs
          no such escalation, just group membership, so it stays useful.
        '';
      };
    };

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
              extraGroups = ["systemd-journal"];
              openssh.authorizedKeys.keys = [
                # Public half of the sops-managed hermes/ssh-key private key
                # (modules/nixos/hermes/default.nix).
                ''from="172.17.0.3",no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOvcTYBeAVez+6x8r4gCOR6eIjBE0oPSYOsW3Qj4znjE hermes-ops fleet key''
              ];
            };
          }
          // lib.genAttrs cfg.journalGrantees (_: {extraGroups = ["systemd-journal"];});
      };

      security.sudo.extraRules = [
        {
          users = ["hermes-ops"];
          commands = startRestartCommands ++ stopCommands ++ [netbirdStatusCommand netbirdExposeCommand];
        }
      ];
    };
  };
}
