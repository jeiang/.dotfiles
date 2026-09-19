{self, ...}: let
  systemctlPath = "/run/current-system/sw/bin/systemctl";

  # sudoers matches the invoked command line literally, arguments included --
  # one entry per (verb, unit) is the only way to permit exactly that
  # (AGENTS.md hermes-ops tiers).
  mkSystemctlCommand = verb: unit: {
    command = "${systemctlPath} ${verb} ${unit}.service";
    options = ["NOPASSWD"];
  };
in {
  nixos.modules.legion = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.hermesOps;

    startRestartCommands =
      lib.concatMap (unit: [(mkSystemctlCommand "start" unit) (mkSystemctlCommand "restart" unit)])
      cfg.tier1Units;
  in {
    options.hermesOps.tier1Units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        This node's tier-1 (restart allowlist, no confirmation) systemd unit
        basenames (AGENTS.md hermes-ops tiers). Set per node by
        modules/hosts/legion/default.nix, not by hand elsewhere.
      '';
    };

    config = {
      users = {
        groups.hermes-ops = {};
        users.hermes-ops = {
          isSystemUser = true;
          group = "hermes-ops";
          home = "/var/empty";
          createHome = false;
          hashedPassword = "!";
          shell = pkgs.bashInteractive;
          extraGroups = ["systemd-journal"];
          openssh.authorizedKeys.keys = [
            # Placeholder: operator generates a real ed25519 keypair and
            # replaces this line; the private half lives in the Hermes
            # secrets shard from the later Hermes PR, never in git.
            ''from="${self.lib.netbirdPeers.artemis}",no-agent-forwarding,no-X11-forwarding ssh-ed25519 REPLACE_ME hermes-ops''
          ];
        };
      };

      security.sudo.extraRules = [
        {
          users = ["hermes-ops"];
          commands = startRestartCommands;
        }
      ];
    };
  };
}
