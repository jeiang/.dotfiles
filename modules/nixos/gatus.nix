{self, ...}: {
  nixos.modules.gatus = _: let
    https = name: group: url: conditions: {
      inherit name group url conditions;
      interval = "2m";
    };

    ok = name: group: url: https name group url ["[STATUS] == 200"];
  in {
    services.gatus = {
      enable = true;
      settings = {
        web.port = self.lib.ports.legion-node4.gatus;

        # In-memory deliberately: keeps this service stateless and off the
        # backup path.
        storage.type = "memory";

        # Scraped by VictoriaMetrics so a failed check reaches Alertmanager;
        # the dashboard alone never notifies anyone.
        metrics = true;

        ui = {
          title = "Status | jeiang.dev";
          header = "jeiang.dev";
          link = "https://jeiang.dev";
          dashboard-heading = "Service Status";
          dashboard-subheading = "Live checks against the fleet's public endpoints";
        };

        endpoints = [
          (ok "Website" "Web" "https://jeiang.dev")
          (ok "aidanpinard.co" "Web" "https://aidanpinard.co")
          (ok "pinard.co.tt" "Web" "https://pinard.co.tt")
          (ok "Portfolio" "Web" "https://noelejoshua.com")
          (ok "Bill Splitter" "Web" "https://bill-split.jeiang.dev")
          (ok "Rivals Randomizer" "Web" "https://rivals.jeiang.dev")
          (ok "Markdown Table Editor" "Web" "https://mdtable.jeiang.dev")

          # /healthz returns 204 No Content; 200 elsewhere is just the SPA
          # fallback, which says nothing about backend health.
          (https "Pocket ID" "Services" "https://auth.jeiang.dev/healthz" ["[STATUS] == 204"])
          (ok "Grafana" "Services" "https://grafana.jeiang.dev/api/health")
          (ok "Actual Budget" "Services" "https://budget.jeiang.dev")
          # "/" falls through to the static dashboard on node1's edge Caddy
          # even when netbird-server is down; this path proxies to node2.
          (ok "NetBird" "Services" "https://netbird.jeiang.dev/oauth2/.well-known/openid-configuration")
          # nix-cache-info is the first request every substituter client makes.
          (ok "Nix cache" "Services" "https://cache.jeiang.dev/nix-cache-info")
          (ok "tinyauth" "Services" "https://tinyauth.jeiang.dev")

          # netbird-proxy has no stable unauthenticated HTTP response, so
          # plain TCP reachability.
          {
            name = "NetBird proxy";
            group = "Services";
            url = "tcp://proxy.jeiang.dev:443";
            interval = "2m";
            conditions = ["[CONNECTED] == true"];
          }

          # cache.jeiang.dev is grey-clouded (DNS-only), so this reads
          # Caddy's own *.jeiang.dev wildcard cert directly, not
          # Cloudflare's edge cert as a proxied hostname would.
          {
            name = "TLS certificate";
            group = "Edge";
            url = "https://cache.jeiang.dev/nix-cache-info";
            interval = "1h";
            conditions = [
              "[STATUS] == 200"
              "[CERTIFICATE_EXPIRATION] > 240h"
            ];
          }
          # proxy.jeiang.dev has its own security.acme cert, renewed
          # separately from the edge wildcard.
          {
            name = "proxy.jeiang.dev certificate";
            group = "Edge";
            url = "tls://proxy.jeiang.dev:443";
            interval = "1h";
            conditions = [
              "[CONNECTED] == true"
              "[CERTIFICATE_EXPIRATION] > 240h"
            ];
          }
        ];
      };
    };

    systemd.services.gatus.serviceConfig.MemoryMax = "64M";
  };
}
