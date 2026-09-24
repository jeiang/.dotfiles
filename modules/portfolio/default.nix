{
  self,
  inputs,
  config,
  ...
}: let
  port = 4321;
  stateDir = "/var/lib/portfolio";
  edge = self.lib.legionNodes.${config.legion.services.caddy.node}.privateIPv4;
in {
  legion.services.portfolio = {
    # Off the edge node: legion-node1 has no restic credentials, and this is
    # the node with the most memory headroom.
    node = "legion-node2";
    module = "portfolio";
    stateful = true;
    units = ["portfolio"];
    ports.app = port;
    firewall = [
      {
        inherit port;
        proto = "tcp";
        scope = "private";
      }
    ];
    # SQLite database and uploads on the root disk. The backup pauses the
    # unit, so the database is never copied mid-write.
    backupSet = [stateDir];
  };

  nixos.modules.portfolio = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.portfolio.nixosModules.default];

    sops.secrets."portfolio/admin-password-hash".sopsFile = ./secrets.yaml;

    services.portfolio = {
      enable = true;
      # Reached from Caddy on legion-node1; the firewall keeps it off the
      # public interface.
      host = "0.0.0.0";
      inherit port stateDir;
      trustedProxies = [edge];
      siteUrl = "https://noelejoshua.com";
      blogUrl = "https://blog.noelejoshua.com";
      adminPasswordHashFile = config.sops.secrets."portfolio/admin-password-hash".path;
    };

    # The root disk holds the only live copy, so the interval is the
    # writing a lost node loses.
    systemd.timers.restic-backups-portfolio.timerConfig = {
      OnCalendar = lib.mkForce "00/12:00";
      RandomizedDelaySec = lib.mkForce "1h";
    };
  };
}
