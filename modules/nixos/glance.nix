{self, ...}: {
  # Glance, the fleet's at-a-glance dashboard, for legion-node4.
  # First-party `services.glance` (DESIGN.md Service Ownership: prefer a
  # first-party module when it fits) -- no custom systemd unit needed.
  #
  # On legion-node4 rather than legion-node2, where it was first written:
  # node2 carries the mesh control plane, SSO and DNS, and once FreshRSS
  # and changedetection.io landed there its declared MemoryMax summed to
  # 2016M against 1922 MiB of RAM. Nothing about this dashboard needs to
  # sit next to those services -- every widget fetches over the network
  # regardless -- so it moved to the node with the headroom.
  # Imported only for the inventory node that places `glance`
  # (modules/hosts/legion/default.nix, same optional-import pattern as
  # blocky/pocket-id).
  #
  # NOT the same thing as `services.glances` (a terminal/web system
  # monitor). Glance is the widget dashboard from glanceapp/glance.
  #
  # Reachability: NetBird peers only, deliberately NOT behind the edge.
  # See the long note above `systemd.services.glance` below -- this is the
  # one design decision in this module that is easy to misread as an
  # oversight.
  flake.nixosModules.glance = _: let
    # Legion private-network addresses (flake.lib.legionNodes,
    # modules/hosts/legion/default.nix), read from the flake rather than
    # copied, same as modules/nixos/edge/default.nix does.
    node3 = self.lib.legionNodes.legion-node3.privateIPv4;

    # Raw VictoriaMetrics on legion-node3
    # (modules/nixos/monitoring/default.nix), reachable over the hcloud
    # private network from this node. Server-side only: Glance itself
    # makes this request, never the browser -- 172.17.0.0/12 is the
    # cross-node private network, which a NetBird-connected browser has no
    # route to. Anything the page links out to must use a public hostname
    # (see the widget's own href below).
    victoriaMetrics = "http://${node3}:8428";
  in {
    services.glance = {
      enable = true;
      settings = {
        server = {
          # The nixpkgs module defaults this to 127.0.0.1, which would make
          # Glance unreachable from anything but legion-node4 itself. Bind
          # every interface instead and scope reachability with the
          # firewall, the same way modules/nixos/blocky.nix does: the
          # NetBird interface's address isn't known at eval time, so an
          # `<ip>:port` pin is impossible.
          host = "0.0.0.0";
          # 8080, the module default, is already taken on this node by
          # netbird-relay (modules/hosts/legion/_service-inventory.nix).
          # 8085 avoids that, blocky's 8000, and pocket-id's 1411.
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
                    # `timezones` (a list), not `timezone` -- the widget's
                    # own clock is always local to the host, and this list
                    # is the extra zones shown beside it
                    # (internal/glance/widget-clock.go). legion-node4 runs
                    # UTC, so the operator's own zone is the useful one.
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
                    # Deliberately overlaps with Gatus (status.jeiang.dev):
                    # Gatus is the durable, public, history-keeping status
                    # page; this is the operator's own instant read on the
                    # same hostnames without leaving the dashboard.
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
                        # garret's puller answers the substituter probe
                        # every `nix` client makes first (docs/adr/0013).
                        title = "Nix cache";
                        url = "https://cache.jeiang.dev/nix-cache-info";
                      }
                    ];
                  }
                  {
                    # Cheap monitoring integration: PromQL straight at
                    # legion-node3's VictoriaMetrics over the private
                    # network, rendered as a single number. `or vector(0)`
                    # matters -- `count()` over an empty vector returns no
                    # samples at all, not 0, so without it the widget
                    # renders an index-out-of-range error precisely when
                    # everything is healthy.
                    type = "custom-api";
                    title = "Scrape targets down";
                    cache = "1m";
                    url = "${victoriaMetrics}/api/v1/query";
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

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    #
    # 64M: Glance is a Go binary holding a handful of cached widget
    # responses in memory and nothing else -- no database, no index, no
    # per-request buffering of anything large. Budgeted against
    # legion-node4's remaining headroom alongside gatus' matching 64M
    # (modules/nixos/gatus.nix).
    systemd.services.glance.serviceConfig.MemoryMax = "64M";

    # --- Why there is no edge route or Pocket ID gate here ---------------
    #
    # Glance 0.8.5 has no OIDC client: its only `auth` mode is a local
    # username plus bcrypt hash (internal/glance/config.go `Auth` struct),
    # which is not Pocket ID and would need its own secret shard. Pocket ID
    # 2.12.0 has no forward-auth endpoint either (nothing in its backend
    # answers a Caddy `forward_auth` subrequest), so there is no target the
    # edge could gate this hostname against without introducing a new
    # service -- oauth2-proxy or similar -- plus a manually registered OIDC
    # client and two new sops secrets.
    #
    # Rather than half-gate a dashboard that aggregates the whole fleet's
    # internal links and monitoring reads, this follows the pattern the
    # repo already uses for services with no native login: reachable from
    # NetBird peers only. `settings.server.host` above binds 0.0.0.0 since
    # the tunnel address is a runtime value, and modules/nixos/netbird.nix
    # (imported fleet-wide) already puts the client's interface in
    # `networking.firewall.trustedInterfaces`. Combined with 8085 never
    # appearing in this node's public/private inventory openings
    # (modules/hosts/legion/_service-inventory.nix `glance.firewall = []`),
    # port 8085 is open on the NetBird interface and nowhere else -- the
    # same mechanism modules/nixos/blocky.nix documents for its 553, and
    # the monitoring module's raw 8428/9428.
    #
    # Putting this on glance.jeiang.dev is a follow-up that needs an
    # operator decision on the auth mechanism first, not a config tweak.
    #
    # Stateless: the config is generated into /run/glance at start and
    # every widget re-fetches on its own cache interval, so there is
    # nothing to retain -- no Volume, no backupSet, matching the `glance`
    # entry in modules/hosts/legion/_service-inventory.nix (stateful =
    # false). The nixpkgs unit's StateDirectory=glance holds nothing Glance
    # actually persists.
  };
}
