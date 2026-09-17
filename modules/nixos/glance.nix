{self, ...}: {
  # Glance the widget dashboard (glanceapp/glance), not `services.glances`.
  flake.nixosModules.glance = {lib, ...}: let
    node3 = self.lib.legionNodes.legion-node3.privateIPv4;
    ports = self.lib.ports;

    # Server-side fetch over the hcloud private network; browsers have no
    # route to 172.17.0.0/12, so anything the page links to must be public.
    victoriaMetrics = "http://${node3}:${toString ports.legion-node3.victoria-metrics}";
    alertmanager = "http://${node3}:${toString ports.legion-node3.alertmanager}";
    grafana = "https://grafana.jeiang.dev";

    vmQuery = query: {
      url = "${victoriaMetrics}/api/v1/query";
      parameters.query = query;
    };
    # `or vector(0)`: an empty instant vector renders as a template error,
    # which is exactly the all-healthy case for most of these counters.
    scalar = expr: "(${expr}) or vector(0)";
    byNode = expr: "(${expr}) * on(instance) group_left(nodename) node_uname_info";
    percentCell = value: ''<td class="text-right">{{ ${value} | printf "%.0f%%" }}</td>'';
    tile = value: label: ''
      <div>
        <div class="color-highlight size-h3">{{ ${value} }}</div>
        <div class="size-h6">${label}</div>
      </div>
    '';

    feed = title: url: {inherit title url;};
  in {
    services.glance = {
      enable = true;
      settings = {
        server = {
          host = "0.0.0.0";
          port = ports.legion-node4.glance;
        };

        branding.logo-text = "legion";

        pages = [
          {
            name = "Home";
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
                  {type = "calendar";}
                  {
                    type = "weather";
                    location = "Port of Spain, Trinidad and Tobago";
                    units = "metric";
                    hour-format = "24h";
                  }
                  {
                    type = "weather";
                    location = "Prior Park, Barbados";
                    units = "metric";
                    hour-format = "24h";
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "rss";
                    title = "Blogs";
                    style = "detailed-list";
                    limit = 30;
                    collapse-after = 8;
                    feeds = [
                      (feed "Xe Iaso" "https://xeiaso.net/blog.rss")
                      (feed "Andrew Kelley" "https://andrewkelley.me/rss.xml")
                      (feed "Zig News" "https://ziglang.org/news/index.xml")
                      (feed "Zig Devlog" "https://ziglang.org/devlog/index.xml")
                      (feed "Rust Blog" "https://blog.rust-lang.org/feed.xml")
                      (feed "This Week in Rust" "https://this-week-in-rust.org/rss.xml")
                      (feed "fasterthanli.me" "https://fasterthanli.me/index.xml")
                      (feed "matklad" "https://matklad.github.io/feed.xml")
                      (feed "without.boats" "https://without.boats/index.xml")
                      (feed "baby steps" "https://smallcultfollowing.com/babysteps/atom.xml")
                      (feed "Mitchell Hashimoto" "https://mitchellh.com/feed.xml")
                      (feed "NixOS Weekly" "https://weekly.nixos.org/feeds/all.rss.xml")
                      (feed "NixOS Announcements" "https://nixos.org/blog/announcements-rss.xml")
                    ];
                  }
                  {
                    type = "hacker-news";
                    limit = 15;
                    collapse-after = 5;
                  }
                  {
                    type = "lobsters";
                    tags = ["zig" "rust" "nix"];
                    limit = 15;
                    collapse-after = 5;
                  }
                ];
              }
            ];
          }
          {
            name = "Fleet";
            columns = [
              {
                size = "small";
                widgets = [
                  {
                    type = "bookmarks";
                    groups = [
                      {
                        title = "Operations";
                        links = [
                          {
                            title = "Grafana";
                            url = grafana;
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
                      {
                        title = "Speed test";
                        # The mesh links are plain http on NetBird peer IPs
                        # and only open when the browser's host is on the mesh.
                        links =
                          [
                            {
                              title = "legion-node1 (public)";
                              url = "https://speed.jeiang.dev";
                            }
                          ]
                          ++ lib.mapAttrsToList (name: ip: {
                            title = "${name} (mesh)";
                            url = "http://${ip}:${toString ports.${name}.librespeed}";
                          })
                          self.lib.netbirdPeers;
                      }
                    ];
                  }
                  {
                    type = "releases";
                    title = "Upstream releases";
                    repositories = [
                      "glanceapp/glance"
                      "pocket-id/pocket-id"
                      "netbirdio/netbird"
                      "TwiN/gatus"
                      "steveiliop56/tinyauth"
                    ];
                  }
                ];
              }
              {
                size = "full";
                widgets = [
                  {
                    type = "custom-api";
                    title = "Firing alerts";
                    title-url = grafana;
                    cache = "1m";
                    url = "${alertmanager}/api/v2/alerts";
                    parameters = {
                      active = "true";
                      silenced = "false";
                      inhibited = "false";
                    };
                    template = ''
                      {{ $alerts := .JSON.Array "" }}
                      {{ if eq (len $alerts) 0 }}
                      <p class="color-positive">No firing alerts</p>
                      {{ else }}
                      <ul class="list list-gap-10 collapsible-container" data-collapse-after="5">
                      {{ range $alerts }}
                        <li>
                          <div class="flex justify-between">
                            <span class="size-h4 color-highlight">{{ .String "labels.alertname" }}</span>
                            <span class="size-h6" {{ .String "startsAt" | parseTime "RFC3339" | toRelativeTime }}></span>
                          </div>
                          <div class="size-h6 text-truncate">{{ .String "annotations.summary" }}</div>
                        </li>
                      {{ end }}
                      </ul>
                      {{ end }}
                    '';
                  }
                  {
                    type = "custom-api";
                    title = "Nodes";
                    title-url = grafana;
                    cache = "1m";
                    inherit
                      (vmQuery ''sort_by_label(${byNode ''100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))''}, "nodename")'')
                      url
                      parameters
                      ;
                    subrequests = {
                      mem = vmQuery (byNode "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)");
                      disk = vmQuery (byNode ''100 * (1 - node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"})'');
                    };
                    template = ''
                      {{ $mem := (.Subrequest "mem").JSON.Array "data.result" }}
                      {{ $disk := (.Subrequest "disk").JSON.Array "data.result" }}
                      <table class="size-h5" style="width: 100%">
                        <thead class="size-h6">
                          <tr><th class="text-left">NODE</th><th class="text-right">CPU</th><th class="text-right">MEM</th><th class="text-right">DISK</th></tr>
                        </thead>
                        <tbody>
                        {{ range .JSON.Array "data.result" }}
                          {{ $node := .String "metric.nodename" }}
                          <tr>
                            <td class="color-highlight">{{ $node }}</td>
                            ${percentCell ''.Float "value.1"''}
                            {{ range $mem }}{{ if eq (.String "metric.nodename") $node }}${percentCell ''.Float "value.1"''}{{ end }}{{ end }}
                            {{ range $disk }}{{ if eq (.String "metric.nodename") $node }}${percentCell ''.Float "value.1"''}{{ end }}{{ end }}
                          </tr>
                        {{ end }}
                        </tbody>
                      </table>
                    '';
                  }
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
                        # /healthz returns 204 No Content; the widget counts
                        # only 200 as up unless listed here.
                        alt-status-codes = [204];
                      }
                      {
                        title = "Actual Budget";
                        url = "https://budget.jeiang.dev";
                      }
                      {
                        title = "Grafana";
                        url = "${grafana}/api/health";
                      }
                      {
                        title = "NetBird";
                        # "/" falls through to node1's static dashboard even
                        # when netbird-server is down; this path proxies to node2.
                        url = "https://netbird.jeiang.dev/oauth2/.well-known/openid-configuration";
                      }
                      {
                        title = "Nix cache";
                        url = "https://cache.jeiang.dev/nix-cache-info";
                      }
                    ];
                  }
                  {
                    type = "custom-api";
                    title = "Services (24h)";
                    title-url = grafana;
                    cache = "5m";
                    inherit (vmQuery (scalar "sum(cs_active_decisions)")) url parameters;
                    subrequests = {
                      blocked = vmQuery (scalar ''100 * sum(increase(blocky_response_total{response_type="BLOCKED"}[24h])) / sum(increase(blocky_query_total[24h]))'');
                      cache-hits = vmQuery (scalar ''100 * sum(increase(garret_narinfo_requests_total{outcome="hit"}[24h])) / sum(increase(garret_narinfo_requests_total[24h]))'');
                      hath = vmQuery (scalar "sum(increase(hath_cache_sent_size_bytes_total[24h])) / 1e9");
                      peers = vmQuery (scalar "sum(signal_active_peers)");
                    };
                    template = ''
                      <div class="flex justify-between text-center">
                        ${tile ''.JSON.Float "data.result.0.value.1" | printf "%.0f"'' "CROWDSEC BANS"}
                        ${tile ''(.Subrequest "blocked").JSON.Float "data.result.0.value.1" | printf "%.0f%%"'' "DNS BLOCKED"}
                        ${tile ''(.Subrequest "cache-hits").JSON.Float "data.result.0.value.1" | printf "%.0f%%"'' "CACHE HITS"}
                        ${tile ''(.Subrequest "hath").JSON.Float "data.result.0.value.1" | printf "%.1f GB"'' "H@H SENT"}
                        ${tile ''(.Subrequest "peers").JSON.Float "data.result.0.value.1" | printf "%.0f"'' "NETBIRD PEERS"}
                      </div>
                    '';
                  }
                  {
                    type = "repository";
                    repository = "jeiang/.dotfiles";
                    pull-requests-limit = 5;
                    issues-limit = 3;
                    commits-limit = 3;
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
