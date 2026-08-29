{self, ...}: {
  flake.nixosModules.freshrss = {
    lib,
    pkgs,
    ...
  }: let
    dataDir = "/mnt/freshrss";

    listenPort = 8087;
  in {
    services = {
      freshrss = {
        enable = true;
        database.type = "sqlite";
        inherit dataDir;
        baseUrl = "https://rss.proxy.jeiang.dev";
        # No app login: the NetBird reverse proxy (Pocket ID SSO) is the
        # only path in.
        authType = "none";
        api.enable = false;
      };

      nginx = {
        # The freshrss module wires the vhost but does not enable nginx itself.
        enable = true;
        virtualHosts.freshrss = {
          # Explicit listen: the vhost default is port 80, which
          # netbird-server binds on this node.
          listen = [
            {
              addr = "0.0.0.0";
              port = listenPort;
            }
          ];
          # Defence in depth, not the boundary: the proxy always stamps
          # X-NetBird-User and strips a client-supplied one first.
          extraConfig = ''
            if ($http_x_netbird_user = "") {
              return 403;
            }
          '';
        };
      };

      # php-fpm refuses to start unless start/min/max spare stay consistent
      # with max_children, so all four move together.
      phpfpm.pools.freshrss.settings = {
        "pm.max_children" = lib.mkForce 3;
        "pm.start_servers" = lib.mkForce 1;
        "pm.min_spare_servers" = lib.mkForce 1;
        "pm.max_spare_servers" = lib.mkForce 2;
      };
    };

    systemd.services = let
      # The module's tmpfiles rule for dataDir is not ordered after the
      # Volume mount; re-assert ownership here since ExecStartPre inherits
      # RequiresMountsFor (mountGuard). `+` runs it as root.
      ensureDataDir = "+${pkgs.coreutils}/bin/install -d -o freshrss -g freshrss -m 0750 ${dataDir}";
    in {
      freshrss-config =
        {
          serviceConfig.ExecStartPre = ensureDataDir;
        }
        // self.lib.mountGuard dataDir;

      freshrss-updater =
        {
          serviceConfig = {
            ExecStartPre = ensureDataDir;
            MemoryMax = "96M";
          };
        }
        // self.lib.mountGuard dataDir;

      phpfpm-freshrss =
        {
          serviceConfig.MemoryMax = "160M";
        }
        // self.lib.mountGuard dataDir;

      nginx.serviceConfig.MemoryMax = "64M";
    };
  };
}
