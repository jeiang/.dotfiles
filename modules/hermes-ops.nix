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
in {
  nixos.modules.legion = {
    config,
    lib,
    pkgs,
    ...
  }: let
    startRestartCommands =
      lib.concatMap (unit: [(mkSystemctlCommand "start" unit) (mkSystemctlCommand "restart" unit)])
      (tier1UnitsFor config.networking.hostName);
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
          ''from="${self.lib.netbirdPeers.artemis}",no-agent-forwarding,no-X11-forwarding ${self.lib.hermesOpsPublicKey}''
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
}
