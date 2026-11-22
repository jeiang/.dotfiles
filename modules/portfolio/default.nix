{
  self,
  inputs,
  ...
}: let
  port = 4321;
  stateDir = "/var/lib/portfolio";
  siteHostname = "noelejoshua.com";
  blogHostname = "blog.noelejoshua.com";
in {
  flake.lib.portfolioHostnames = [siteHostname blogHostname];

  legion.services.portfolio = {
    # Off the edge node: alda has no restic credentials, and this is
    # the node with the most memory headroom.
    node = "vida";
    module = "portfolio";
    stateful = true;
    units = ["portfolio"];
    ports.app = port;
    # The backup pauses the unit, so the SQLite database is never copied
    # mid-write.
    backupSet = [stateDir];
  };

  nixos.modules.portfolio = {
    config,
    pkgs,
    ...
  }: {
    imports = [inputs.portfolio.nixosModules.default];

    sops.secrets."portfolio/admin-password-hash".sopsFile = ./secrets.yaml;

    services.portfolio = {
      enable = true;
      package = inputs.portfolio.packages.${pkgs.stdenv.hostPlatform.system}.portfolio;
      # Reached from Caddy on the edge node; the firewall keeps it off the
      # public interface.
      host = "0.0.0.0";
      inherit port stateDir;
      trustedProxies = [(self.lib.serviceAddress config.networking.hostName "caddy")];
      siteUrl = "https://${siteHostname}";
      blogUrl = "https://${blogHostname}";
      adminPasswordHashFile = config.sops.secrets."portfolio/admin-password-hash".path;
    };

    backups.jobs.portfolio.schedule = {
      onCalendar = "00/12:00";
      randomizedDelaySec = "1h";
    };

    # The site is its owner's unreviewed code: it answers the edge and reaches nothing else.
    systemd.services.portfolio.serviceConfig = {
      IPAddressDeny = "any";
      IPAddressAllow = [(self.lib.serviceAddress config.networking.hostName "caddy")];
    };
  };
}
