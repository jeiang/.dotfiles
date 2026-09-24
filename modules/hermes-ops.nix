{
  self,
  lib,
  config,
  ...
}: let
  systemctlPath = "/run/current-system/sw/bin/systemctl";

  # sudoers matches the invoked command line literally, arguments included --
  # one entry per (verb, unit) is the only way to permit exactly that
  # (AGENTS.md hermes-ops tiers).
  mkSystemctlCommand = verb: unit: {
    command = "${systemctlPath} ${verb} ${unit}.service";
    options = ["NOPASSWD"];
  };

  servicesByNode = nodeName: builtins.filter (s: s.node == nodeName) (lib.mapAttrsToList (name: s: s // {inherit name;}) config.legion.services);

  # AGENTS.md hermes-ops tiers: every unit of these whole services is tier 1
  # (restart allowlist); prometheus-blackbox-exporter is tier 1 too, but
  # rides inside the otherwise tier-2 monitoring service, so it is picked
  # out by unit name instead.
  tier1Services = ["gatus" "glance" "garret" "hath" "crowdsec"];
  tier1PickedUnits = ["prometheus-blackbox-exporter"];
  nodeExporterUnit = "prometheus-node-exporter";

  tier1UnitsFor = nodeName: let
    services = servicesByNode nodeName;
    wholeServiceUnits = lib.concatMap (s: s.units) (builtins.filter (s: builtins.elem s.name tier1Services) services);
    pickedUnits = lib.concatMap (s: builtins.filter (u: builtins.elem u tier1PickedUnits) s.units) services;
    resticBackupUnits = map (s: "restic-backups-${s.name}") (builtins.filter (s: s.backupSet != [] && s.volume != null) services);
  in
    [nodeExporterUnit] ++ wholeServiceUnits ++ pickedUnits ++ resticBackupUnits;

  # Some legion.services units are node-exporter regexes ("acme-.*"); sudoers
  # needs literal unit names, so those stay tier 3.
  isLiteralUnit = unit: builtins.match "[A-Za-z0-9_@:-]+" unit != null;

  tier2UnitsFor = nodeName: let
    tier1 = tier1UnitsFor nodeName;
  in
    builtins.filter (u: isLiteralUnit u && !(builtins.elem u tier1)) (lib.concatMap (s: s.units) (servicesByNode nodeName));

  # AGENTS.md hermes-ops tiers: stop on a tier-1 unit, and start/stop/restart
  # on every other literal legion.services unit.
  tier2CommandsFor = nodeName:
    map (unit: {
      verb = "stop";
      inherit unit;
    }) (tier1UnitsFor nodeName)
    ++ lib.concatMap (unit:
      map (verb: {inherit verb unit;}) ["start" "stop" "restart"])
    (tier2UnitsFor nodeName);
in {
  # Per node, the (verb, unit) pairs hermes-t2 may run; the artemis approver
  # renders its allowlist from the same attrset.
  flake.lib.hermesTier2Commands = lib.genAttrs (builtins.attrNames self.lib.legionNodes) tier2CommandsFor;

  nixos.modules.legion = {
    config,
    lib,
    pkgs,
    ...
  }: let
    nodeName = config.networking.hostName;
    startRestartCommands =
      lib.concatMap (unit: [(mkSystemctlCommand "start" unit) (mkSystemctlCommand "restart" unit)])
      (tier1UnitsFor nodeName);
    tier2Commands = map ({
      verb,
      unit,
    }:
      mkSystemctlCommand verb unit)
    self.lib.hermesTier2Commands.${nodeName};
  in {
    users = {
      groups = {
        hermes-ops = {};
        hermes-t2 = {};
      };
      users = {
        hermes-ops = {
          isSystemUser = true;
          group = "hermes-ops";
          home = "/var/empty";
          createHome = false;
          hashedPassword = "!";
          shell = pkgs.bashInteractive;
          extraGroups = ["systemd-journal"];
          openssh.authorizedKeys.keys = [
            ''from="${self.lib.netbirdPeers.artemis}",no-agent-forwarding,no-X11-forwarding ${self.lib.hermesOpsPublicKey}''
          ];
        };
        # Tier 2: only the artemis approver (modules/hermes/approver) holds
        # this key, and runs a command only after the operator approves it.
        hermes-t2 = {
          isSystemUser = true;
          group = "hermes-t2";
          home = "/var/empty";
          createHome = false;
          hashedPassword = "!";
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = [
            ''from="${self.lib.netbirdPeers.artemis}",restrict ${self.lib.hermesTier2PublicKey}''
          ];
        };
      };
    };

    security.sudo.extraRules = [
      {
        users = ["hermes-ops"];
        commands = startRestartCommands;
      }
      {
        users = ["hermes-t2"];
        commands = tier2Commands;
      }
    ];
  };
}
