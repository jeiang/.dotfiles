{self, ...}: {
  # Glance the widget dashboard (glanceapp/glance), not `services.glances`.
  flake.nixosModules.glance = _: let
    node3 = self.lib.legionNodes.legion-node3.privateIPv4;

    # Server-side fetch over the hcloud private network; browsers have no
    # route to 172.17.0.0/12, so anything the page links to must be public.
    victoriaMetrics = "http://${node3}:${toString self.lib.ports.legion-node3.victoria-metrics}";
  in {
    services.glance = {
      enable = true;
      settings = {
        server = {
          host = "0.0.0.0";
          port = 8085;
        };

        branding.logo-text = "legion";

        pages = [
          {
            name = "Fleet";
            columns = [
              {
                size = "small";
                widgets = [
                  {
                    type = "clock";
                    hour-format = "24h";
                    # The widget's own clock is always host-local; `timezones`
                    # adds extra zones beside it.
                    timezones = [
                      {
                        timezone = "America/Port_of_Spain";
                        label = "Local";
                      }
                    ];
                  }
                  {
                    type = "bookmarks";
                    groups = [
                      {
                        title = "Operations";
                        links = [
                          {
                            title = "Grafana";
                            url = "https://grafana.jeiang.dev";
                          }
                          {
                            title = "Status";
                            url = "https://status.jeiang.dev";
                          }
                          {
                            title = "NetBird";
                            url = "https://netbird.jeiang.dev";
                          }
                          {
                            title = "Pocket ID";
                            url = "https://auth.jeiang.dev";
                          }
                        ];
                      }
                      {
                        title = "Apps";
                        links = [
                          {
                            title = "Actual Budget";
                            url = "https://budget.jeiang.dev";
                          }
                          {
                            title = "Bill Splitter";
                            url = "https://bill-split.jeiang.dev";
                          }
                          {
                            title = "Rivals Randomizer";
                            url = "https://rivals.jeiang.dev";
                          }
                          {
                            title = "Markdown Table Editor";
                            url = "https://mdtable.jeiang.dev";
                          }
                        ];
                      }
                    ];
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "monitor";
                    title = "Public endpoints";
                    cache = "5m";
                    sites = [
                      {
                        title = "Website";
                        url = "https://jeiang.dev";
                      }
                      {
                        title = "Portfolio";
                        url = "https://noelejoshua.com";
                      }
                      {
                        title = "Pocket ID";
                        url = "https://auth.jeiang.dev/healthz";
                      }
                      {
                        title = "Actual Budget";
                        url = "https://budget.jeiang.dev";
                      }
                      {
                        title = "Grafana";
                        url = "https://grafana.jeiang.dev/api/health";
                      }
                      {
                        title = "NetBird";
                        url = "https://netbird.jeiang.dev";
                      }
                      {
                        title = "Nix cache";
                        url = "https://cache.jeiang.dev/nix-cache-info";
                      }
                    ];
                  }
                  {
                    type = "custom-api";
                    title = "Scrape targets down";
                    cache = "1m";
                    url = "${victoriaMetrics}/api/v1/query";
                    # `or vector(0)`: count() over an empty vector returns no
                    # samples at all, which renders as an error precisely when
                    # everything is healthy.
                    parameters.query = "count(up == 0) or vector(0)";
                    template = ''
                      <div class="flex justify-between">
                        <a class="size-h3 color-highlight" href="https://grafana.jeiang.dev" target="_blank">{{ .JSON.String "data.result.0.value.1" }}</a>
                        <div class="size-h6">targets down</div>
                      </div>
                    '';
                  }
                ];
              }
            ];
          }
        ];
      };
    };

    systemd.services.glance.serviceConfig.MemoryMax = "64M";
  };
}
