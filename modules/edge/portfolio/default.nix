{
  self,
  inputs,
  ...
}: let
  port = 4321;
  stateDir = "/var/lib/portfolio";
  siteHostname = "noelejoshua.com";
  blogHostname = "blog.noelejoshua.com";
  learnHostname = "learn.noelejoshua.com";
in {
  flake.lib.portfolioHostnames = [siteHostname blogHostname learnHostname];

  gatus.endpoints = {
    Portfolio = {
      group = "Web";
      url = "https://${siteHostname}";
      conditions = ["[STATUS] == 200" "[BODY] == pat(*Joshua Noel*)"];
    };
    "Portfolio blog" = {
      group = "Web";
      url = "https://${blogHostname}";
      conditions = ["[STATUS] == 200" "[BODY] == pat(*Writing*)"];
    };
    "Portfolio lectures" = {
      group = "Web";
      url = "https://${learnHostname}";
      conditions = ["[STATUS] == 200" "[BODY] == pat(*Joshua Noel*)"];
    };
  };

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
      learnUrl = "https://${learnHostname}";
      # The lectures are a public repository pinned as a flake input: a
      # store path, read-only, with nothing private in it.
      learnContentDirs = [inputs.learn-content];
      adminPasswordHashFile = config.sops.secrets."portfolio/admin-password-hash".path;
    };

    # Stealth release, at the owner's request: the lectures answer at their
    # address but are not indexed, are left out of every sitemap and feed,
    # and the main site and blog do not link to them. Remove this line to
    # launch.
    systemd.services.portfolio.environment.PORTFOLIO_LEARN_STEALTH = "1";

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
