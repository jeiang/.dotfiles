{
  self,
  inputs,
  config,
  ...
}: let
  port = 4321;
  stateDir = "/var/lib/portfolio";
  buildDir = "/var/lib/portfolio-update";
  edge = self.lib.legionNodes.${config.legion.services.caddy.node}.privateIPv4;
in {
  legion.services.portfolio = {
    # Off the edge node: alda has no restic credentials, and this is
    # the node with the most memory headroom.
    node = "vida";
    module = "portfolio";
    stateful = true;
    units = ["portfolio" "portfolio-update"];
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
    pkgs,
    ...
  }: let
    pinned = inputs.portfolio.packages.${pkgs.stdenv.hostPlatform.system}.portfolio;
  in {
    imports = [inputs.portfolio.nixosModules.default];

    sops.secrets."portfolio/admin-password-hash".sopsFile = ./secrets.yaml;

    services.portfolio = {
      enable = true;
      # The site is built from upstream main by portfolio-update, so its
      # owner's changes land without a flake bump. The pinned input is the
      # fallback until the first build exists.
      package = pkgs.writeShellScriptBin "portfolio" ''
        if [ -x ${buildDir}/current/bin/portfolio ]; then
          exec ${buildDir}/current/bin/portfolio
        fi
        exec ${lib.getExe pinned}
      '';
      # Reached from Caddy on alda; the firewall keeps it off the
      # public interface.
      host = "0.0.0.0";
      inherit port stateDir;
      trustedProxies = [edge];
      siteUrl = "https://noelejoshua.com";
      blogUrl = "https://blog.noelejoshua.com";
      adminPasswordHashFile = config.sops.secrets."portfolio/admin-password-hash".path;
    };

    # Starting portfolio-update after a snapshot would rebuild needlessly.
    backups.jobs.portfolio.pauseUnits = ["portfolio.service"];

    systemd = {
      # The build runs unprivileged, so third-party flake evaluation never
      # runs as root; only the restart does.
      services.portfolio-update = {
        description = "Build the portfolio from upstream main";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [config.nix.package];
        serviceConfig = {
          Type = "oneshot";
          User = config.services.portfolio.user;
          Group = config.services.portfolio.group;
          WorkingDirectory = buildDir;
          StateDirectory = "portfolio-update";
          ExecStartPost = "+${pkgs.writeShellScript "portfolio-restart" ''
            if [ -e ${buildDir}/restart ]; then
              rm ${buildDir}/restart
              ${config.systemd.package}/bin/systemctl try-restart portfolio.service
            fi
          ''}";
        };
        script = ''
          set -euo pipefail
          export HOME=${buildDir}
          old=$(readlink current || true)
          nix build --refresh --out-link current github:joshua-noel/portfolio#portfolio
          [ "$(readlink current)" = "$old" ] || touch restart
        '';
      };

      timers.portfolio-update = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-* 00:00:00 UTC";
          Persistent = true;
          OnActiveSec = "2m";
        };
      };

      # The root disk holds the only live copy, so the interval is the
      # writing a lost node loses.
      timers.restic-backups-portfolio.timerConfig = {
        OnCalendar = lib.mkForce "00/12:00";
        RandomizedDelaySec = lib.mkForce "1h";
      };
    };
  };
}
