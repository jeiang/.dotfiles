{self, ...}: {
  flake.nixosModules.gatus = _: let
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

          (ok "Pocket ID" "Services" "https://auth.jeiang.dev/healthz")
          (ok "Grafana" "Services" "https://grafana.jeiang.dev/api/health")
          (ok "Actual Budget" "Services" "https://budget.jeiang.dev")
          # 401, not 200: the edge's basic_auth challenge is proof the gate
          # and the route are up; a 200 would mean the gate is gone.
          (https "Color Hunt" "Services" "https://color-hunt.jeiang.dev" ["[STATUS] == 401"])
          (ok "NetBird" "Services" "https://netbird.jeiang.dev")
          # nix-cache-info is the first request every substituter client makes.
          (ok "Nix cache" "Services" "https://cache.jeiang.dev/nix-cache-info")

          # netbird-proxy has no stable unauthenticated HTTP response, so
          # plain TCP reachability.
          {
            name = "NetBird proxy";
            group = "Services";
            url = "tcp://proxy.jeiang.dev:443";
            interval = "2m";
            conditions = ["[CONNECTED] == true"];
          }

          # The edge's wildcard cert covers every *.jeiang.dev hostname, so
          # one certificate check on the apex covers all of them.
          {
            name = "TLS certificate";
            group = "Edge";
            url = "https://jeiang.dev";
            interval = "1h";
            conditions = [
              "[STATUS] == 200"
              "[CERTIFICATE_EXPIRATION] > 240h"
            ];
          }
        ];
      };
    };

    systemd.services.gatus.serviceConfig.MemoryMax = "64M";
  };
}
