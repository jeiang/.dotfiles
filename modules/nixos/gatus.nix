_: {
  # Gatus, the public status page, for legion-node4, behind the edge at
  # status.jeiang.dev (modules/nixos/edge/default.nix
  # `status.jeiang.dev { reverse_proxy ${node4}:8086 }`). First-party
  # `services.gatus` (DESIGN.md Service Ownership) -- no custom systemd
  # unit needed. Imported only for the inventory node that places `gatus`
  # (modules/hosts/legion/default.nix, same optional-import pattern as
  # pocket-id/blocky).
  #
  # Placement, in order of what it rules out. Not legion-node3, beside the
  # monitoring stack: a status page that shares a node with the thing it
  # reports on goes down with it. Not legion-node1, the edge: an edge
  # outage would take the page down along with everything it is meant to
  # explain. Not legion-node2, which was the original choice and is where
  # the module was first written -- node2 carries the mesh control plane,
  # SSO and DNS, and once FreshRSS and changedetection.io landed there its
  # declared MemoryMax summed to 2016M against 1922 MiB of RAM. That
  # leaves legion-node4, which has the headroom and, usefully, does not
  # run Pocket ID -- one of the services checked below.
  flake.nixosModules.gatus = _: let
    # Every check is HTTPS against a hostname that already resolves
    # publicly (modules/hosts/legion/_service-inventory.nix `caddy`
    # publicHostnames). See the "why nothing internal is checked here"
    # note at the bottom.
    https = name: group: url: conditions: {
      inherit name group url conditions;
      interval = "2m";
    };

    # Status-only check, the common case: the edge answered and the
    # backend behind it did too.
    ok = name: group: url: https name group url ["[STATUS] == 200"];
  in {
    services.gatus = {
      enable = true;
      settings = {
        # 8080 (the module default) is netbird-relay's on this node, 8085
        # is glance's, 8000 is blocky's, 1411 is pocket-id's
        # (modules/hosts/legion/_service-inventory.nix). 8086 is free.
        web.port = 8086;

        # In-memory store, Gatus' own default, stated explicitly because
        # it is the deliberate choice that keeps this service off the
        # backup path entirely (DESIGN.md State And Backup Boundaries).
        # The alternative -- `type = "sqlite"` with a path -- would make
        # Gatus stateful, which the Legion inventory then requires to
        # declare a Hetzner Volume for (the
        # `statefulServicesWithoutVolume` assert in
        # _service-inventory.nix), to provision that Volume out of band,
        # and to carry a Backup Set. All of that to retain a rolling
        # window of uptime samples that legion-node3's VictoriaMetrics
        # already keeps for real, from a scrape path that survives this
        # node. Losing the history on restart is the cheaper side of that
        # trade.
        storage.type = "memory";

        ui = {
          title = "Status | jeiang.dev";
          header = "jeiang.dev";
          link = "https://jeiang.dev";
          dashboard-heading = "Service Status";
          dashboard-subheading = "Live checks against the fleet's public endpoints";
        };

        # No `metrics: true`. Gatus serves its Prometheus metrics on the
        # same listener as the dashboard, and this listener is public --
        # exposing them would publish per-endpoint response-time series to
        # anyone. legion-node3's monitoring stack already scrapes these
        # services at their source.

        endpoints = [
          (ok "Website" "Web" "https://jeiang.dev")
          (ok "aidanpinard.co" "Web" "https://aidanpinard.co")
          (ok "pinard.co.tt" "Web" "https://pinard.co.tt")
          (ok "Portfolio" "Web" "https://noelejoshua.com")
          (ok "Bill Splitter" "Web" "https://bill-split.jeiang.dev")
          (ok "Rivals Randomizer" "Web" "https://rivals.jeiang.dev")
          (ok "Markdown Table Editor" "Web" "https://mdtable.jeiang.dev")

          # Each of these hits an endpoint the application itself answers,
          # not just Caddy's site block, so a proxied-but-dead backend
          # still reads down.
          (ok "Pocket ID" "Services" "https://auth.jeiang.dev/healthz")
          (ok "Grafana" "Services" "https://grafana.jeiang.dev/api/health")
          (ok "Actual Budget" "Services" "https://budget.jeiang.dev")
          (ok "NetBird" "Services" "https://netbird.jeiang.dev")
          # garret's puller: `nix-cache-info` is the first request every
          # substituter client makes (docs/adr/0013), so this is the check
          # that actually predicts whether a build can use the cache.
          # cache-push.jeiang.dev has no equivalent unauthenticated GET --
          # its API is push-only -- so it is deliberately absent.
          (ok "Nix cache" "Services" "https://cache.jeiang.dev/nix-cache-info")

          # netbird-proxy terminates its own TLS on its own public :443
          # and does not resolve through the edge
          # (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md).
          # It has no stable unauthenticated HTTP response to assert on,
          # so this is a plain TCP reachability check instead.
          {
            name = "NetBird proxy";
            group = "Services";
            url = "tcp://proxy.jeiang.dev:443";
            interval = "2m";
            conditions = ["[CONNECTED] == true"];
          }

          # The edge's wildcard cert covers every *.jeiang.dev hostname
          # above, so one certificate check on the apex covers all of them
          # -- and catches a DNS-01 renewal that quietly stopped working
          # weeks before the cert would actually expire.
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

    # 64M: Gatus holds `storage.maximum-number-of-results` (100 by
    # default) samples per endpoint in memory and nothing else -- roughly
    # a dozen endpoints here. Budgeted against legion-node4's remaining
    # headroom alongside glance's matching 64M (modules/nixos/glance.nix).
    systemd.services.gatus.serviceConfig.MemoryMax = "64M";

    # --- Why this hostname is public and ungated -------------------------
    #
    # A status page behind SSO is unreachable in exactly the situation it
    # exists for: Pocket ID (auth.jeiang.dev) is itself one of the
    # services being monitored, and it sits behind the same edge Caddy, so
    # gating this hostname would mean an edge or IdP outage takes the
    # outage report down with it. Publishing it through netbird-proxy
    # instead was considered and fails for the same reason: the proxy
    # authenticates against Pocket ID, so it inherits exactly the
    # dependency this needs to avoid. Public and ungated is the only
    # posture that survives its own failure modes.
    #
    # That posture is what constrains the check list above to hostnames
    # that already resolve publicly. Gatus' dashboard API
    # (/api/v1/endpoints/statuses) is served on the same public listener
    # and echoes each result's `hostname`
    # (config/endpoint/result.go), so an internal check against
    # 172.17.0.x would publish the fleet's private topology to anyone who
    # loads the page. Nothing here is lost by that: every check above
    # traverses the edge and reaches the real backend, so internal service
    # health is still what is being measured -- just end-to-end, through
    # the path a user actually takes. Internal-only health (raw
    # VictoriaMetrics/VictoriaLogs, blocky, the relays) stays where it
    # already lives, in legion-node3's vmalert and Alertmanager.
    #
    # Stateless (`storage.type = "memory"` above): no Volume, no
    # backupSet, matching the `gatus` entry in
    # modules/hosts/legion/_service-inventory.nix (stateful = false).
  };
}
