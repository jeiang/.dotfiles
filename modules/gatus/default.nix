{
  self,
  config,
  lib,
  ...
}: let
  port = 8086;

  https = name: group: url: conditions: {
    inherit name group url conditions;
    interval = "2m";
  };

  ok = name: group: url: https name group url ["[STATUS] == 200"];

  # A body assertion beside status: an empty 200 slipped past status-only
  # checks on 2026-09-18 and nothing alerted.
  page = name: group: url: needle:
    https name group url ["[STATUS] == 200" "[BODY] == pat(*${needle}*)"];

  base = {
    web.port = port;

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

    endpoints =
      [
        (page "Website" "Web" "https://jeiang.dev" "Aidan Pinard - Home")
        (page "aidanpinard.co" "Web" "https://aidanpinard.co" "Aidan Pinard - Home")
        (page "pinard.co.tt" "Web" "https://pinard.co.tt" "Aidan Pinard - Home")
        (page "Portfolio" "Web" "https://noelejoshua.com" "Joshua Noel")
        (page "Portfolio blog" "Web" "https://blog.noelejoshua.com" "Writing")
        (ok "Bill Splitter" "Web" "https://bill-split.jeiang.dev")
        (ok "Rivals Randomizer" "Web" "https://rivals.jeiang.dev")
        (ok "Markdown Table Editor" "Web" "https://mdtable.jeiang.dev")

        # /healthz returns 204 No Content; 200 elsewhere is just the SPA
        # fallback, which says nothing about backend health.
        (https "Pocket ID" "Services" "${self.lib.pocketIdUrl}/healthz" ["[STATUS] == 204"])
        (ok "Grafana" "Services" "https://${self.lib.grafanaHostname}/api/health")
        # "/" falls through to the static dashboard on node1's edge Caddy
        # even when netbird-server is down; this path proxies to node2.
        (ok "NetBird" "Services" "https://${self.lib.netbirdDomain}/oauth2/.well-known/openid-configuration")
        # nix-cache-info is the first request every substituter client makes.
        (ok "Nix cache" "Services" "https://${self.lib.cacheHostname}/nix-cache-info")
        (ok "tinyauth" "Services" "https://${self.lib.tinyauthHostname}")
        (ok "ntfy" "Services" "${self.lib.ntfyBaseUrl}/v1/health")

        # netbird-proxy has no stable unauthenticated HTTP response, so plain
        # TCP reachability, per replica: proxy.jeiang.dev resolves to all of them.
      ]
      ++ map (service: let
        node = config.legion.services.${service}.node;
      in {
        name = "NetBird proxy (${node})";
        group = "Services";
        url = "tcp://${self.lib.legionNodes.${node}.publicIPv4}:443";
        interval = "2m";
        conditions = ["[CONNECTED] == true"];
      })
      self.lib.netbirdProxyServices
      ++ [
        # ntfy.jeiang.dev is grey-clouded (DNS-only), so this reads
        # Caddy's own *.jeiang.dev wildcard cert directly, not
        # Cloudflare's edge cert as a proxied hostname would.
        {
          name = "TLS certificate";
          group = "Edge";
          url = "${self.lib.ntfyBaseUrl}/v1/health";
          interval = "1h";
          conditions = [
            "[STATUS] == 200"
            "[CERTIFICATE_EXPIRATION] > 240h"
          ];
        }
        # The cache and regional ingress renew independently of the edge wildcard.
        {
          name = "${self.lib.cacheHostname} certificate";
          group = "Edge";
          url = "https://${self.lib.cacheHostname}/nix-cache-info";
          interval = "1h";
          conditions = [
            "[STATUS] == 200"
            "[CERTIFICATE_EXPIRATION] > 240h"
          ];
        }
        # proxy.jeiang.dev has its own security.acme cert on each replica,
        # renewed separately from the edge wildcard; each run reaches one of them.
        {
          name = "${self.lib.netbirdProxyDomain} certificate";
          group = "Edge";
          url = "tls://${self.lib.netbirdProxyDomain}:443";
          interval = "1h";
          conditions = [
            "[CONNECTED] == true"
            "[CERTIFICATE_EXPIRATION] > 240h"
          ];
        }
      ];
  };

  # The Anubis-protected sites resolve to the edge's private or mesh
  # address, which the edge serves without a challenge.
  contentSiteHosts = hostName: {
    ${self.lib.legionAddress hostName config.legion.services.caddy.node} = self.lib.websiteHostnames ++ self.lib.portfolioHostnames;
  };

  instance = {
    settings,
    alerts ? [],
  }: {config, ...}: {
    networking.hosts = contentSiteHosts config.networking.hostName;

    services.gatus = {
      enable = true;
      settings =
        base
        // settings
        // lib.optionalAttrs (alerts != []) {
          endpoints = map (endpoint: endpoint // {inherit alerts;}) base.endpoints;
        };
    };

    systemd.services.gatus = {
      serviceConfig.MemoryMax = "64M";
      # A running Gatus keeps resolving through the hosts table it started with.
      restartTriggers = [(builtins.toJSON config.networking.hosts)];
    };
  };

  placement = {
    gatus = "zantark";
    gatus-atl = "ricklent";
  };
in {
  flake.lib = {
    statusHostname = "status.jeiang.dev";
    gatusServices = builtins.attrNames placement;
  };

  legion.services =
    lib.mapAttrs (module: node: {
      inherit node module;
      units = ["gatus"];
      ports.app = port;
    })
    placement;

  nixos.modules = {
    gatus = instance {
      # Scraped by VictoriaMetrics so a failed check reaches Alertmanager;
      # the dashboard alone never notifies anyone.
      settings.metrics = true;
    };

    # Alerts straight to Discord so the watchdog does not depend on zantark.
    gatus-atl = {config, ...}: {
      imports = [
        (instance {
          settings.alerting.discord = {
            webhook-url = "\${DISCORD_WEBHOOK_URL}";
            default-alert = {
              failure-threshold = 5;
              success-threshold = 2;
              send-on-resolved = true;
            };
          };
          alerts = [{type = "discord";}];
        })
      ];

      services.gatus.environmentFile = config.sops.templates."gatus.env".path;

      sops = {
        secrets."discord-webhook".sopsFile = ./secrets.yaml;
        templates."gatus.env" = {
          restartUnits = ["gatus.service"];
          content = "DISCORD_WEBHOOK_URL=${config.sops.placeholder."discord-webhook"}\n";
        };
      };
    };
  };
}
