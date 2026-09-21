{
  self,
  lib,
  config,
  ...
}: let
  systemctlPath = "/run/current-system/sw/bin/systemctl";

  # AGENTS.md hermes-ops tiers: every unit of these whole services is tier 1
  # (start/restart, no approval); prometheus-blackbox-exporter is tier 1 too,
  # but rides inside the otherwise tier-2 monitoring service, so it is picked
  # out by unit name instead. Every other unit of a node's services is tier 2,
  # and so is `stop` on a tier-1 unit.
  tier1Services = ["gatus" "glance" "garret" "hath" "crowdsec"];
  tier1PickedUnits = ["prometheus-blackbox-exporter"];
  nodeExporterUnit = "prometheus-node-exporter";

  # A sudoers command is a glob, so a `legion.services.<name>.units` entry
  # written as a regex for the node-exporter unit-include (netbird-proxy's
  # `acme-.*`) would turn its rule into a wildcard. Only literal unit names
  # get a tier.
  literalUnits = builtins.filter (u: builtins.match "[A-Za-z0-9@._-]+" u != null);

  # The remote argv, not a shell string: the sudoers rules below render each
  # entry with the absolute systemctl path, and the approval gate in
  # modules/hermes/tier2 matches Hermes' terminal command against this text.
  systemctlCommand = verb: unit: "systemctl ${verb} ${unit}.service";

  servicesByNode = nodeName:
    builtins.filter (s: s.node == nodeName)
    (lib.mapAttrsToList (name: s: s // {inherit name;}) config.legion.services);

  hermesOpsCommands =
    lib.mapAttrs (
      name: _: let
        services = servicesByNode name;
        allUnits = literalUnits (lib.unique (lib.concatMap (s: s.units) services));
        wholeServiceUnits = literalUnits (lib.concatMap (s: s.units) (builtins.filter (s: builtins.elem s.name tier1Services) services));
        pickedUnits = builtins.filter (u: builtins.elem u tier1PickedUnits) allUnits;
        resticBackupUnits = map (s: "restic-backups-${s.name}") (builtins.filter (s: s.backupSet != [] && s.volume != null) services);
        tier1Units = lib.unique ([nodeExporterUnit] ++ wholeServiceUnits ++ pickedUnits ++ resticBackupUnits);
        tier2Units = builtins.filter (u: !(builtins.elem u tier1Units)) allUnits;
      in {
        tier1 = lib.concatMap (u: [(systemctlCommand "start" u) (systemctlCommand "restart" u)]) tier1Units;
        tier2 =
          map (systemctlCommand "stop") tier1Units
          ++ lib.concatMap (u: [(systemctlCommand "start" u) (systemctlCommand "restart" u) (systemctlCommand "stop" u)]) tier2Units
          ++ ["systemctl reboot"];
      }
    )
    self.lib.legionNodes;
in {
  flake.lib.hermesOpsCommands = hermesOpsCommands;

  nixos.modules.legion = {
    config,
    lib,
    pkgs,
    ...
  }: let
    commands = hermesOpsCommands.${config.networking.hostName};

    # sudoers matches the invoked command line literally, arguments included --
    # one entry per exact command is the only way to permit exactly that. Tier 2
    # gets a rule of the same shape as tier 1: the approval gate runs on
    # artemis, so the rule here only bounds what an approved tier-2 command is
    # allowed to be.
    mkRule = command: {
      command = "${systemctlPath} ${lib.removePrefix "systemctl " command}";
      options = ["NOPASSWD"];
    };
  in {
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
          # The public half of modules/hermes's hermes/ssh-key secret;
          # self.lib.hermesOpsPublicKey is a placeholder until the
          # operator mints the real keypair.
          ''from="${self.lib.netbirdPeers.artemis}",no-agent-forwarding,no-X11-forwarding ${self.lib.hermesOpsPublicKey}''
        ];
      };
    };

    security.sudo.extraRules = [
      {
        users = ["hermes-ops"];
        commands = map mkRule (commands.tier1 ++ commands.tier2);
      }
    ];
  };
}
