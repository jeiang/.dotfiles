{
  self,
  inputs,
  ...
}: {
  # Edge Node Caddy. Imported only for the inventory's edge node
  # (modules/hosts/legion/default.nix).
  flake.nixosModules.edge = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.edge;
    system = pkgs.stdenv.hostPlatform.system;

    # Legion private-network addresses (flake.lib.legionNodes,
    # modules/hosts/legion/default.nix).
    node1 = self.lib.legionNodes.legion-node1.privateIPv4; # This node's own private address (metrics bind)
    node2 = self.lib.legionNodes.legion-node2.privateIPv4; # NetBird server/relay, Pocket ID
    node3 = self.lib.legionNodes.legion-node3.privateIPv4; # Monitoring/Grafana
    node4 = self.lib.legionNodes.legion-node4.privateIPv4; # garret, Actual Budget

    website = inputs.website.packages.${system}.default;
    portfolio = "${inputs.portfolio.packages.${system}.default}/dist";
    billSplitter = "${inputs.bill-splitter.packages.${system}.default}/dist";
    rivalsRandomizer = inputs.character-randomizer.packages.${system}.default;
    netbirdDashboard = config.services.netbird.server.dashboard.finalDrv;
    netbirdIronRDP = self.packages.${system}.netbird-ironrdp-web;

    # Bare `crowdsec`/`appsec` HTTP handler directives (below, gated on
    # cfg.crowdsec.enable so a disabled toggle renders byte-identical
    # output to before this existed). Each already carries its own
    # trailing newline + indent so callers just concatenate them ahead of
    # the site block's first real directive.
    crowdsecLine = lib.optionalString cfg.crowdsec.enable "crowdsec\n            ";
    appsecLine = lib.optionalString cfg.crowdsec.enable "appsec\n            ";

    # Bare `log` directive, same concatenation pattern as crowdsecLine/appsecLine
    # above. Caddy 2's HTTP access logging is opt-in per site block -- with
    # no `log` directive a site produces zero access records, even though
    # the named `journald` logger declared in globalConfig below exists and
    # is reachable. Added unconditionally (not gated on cfg.crowdsec.enable)
    # to every public site block except the private-network-only metrics
    # listener (logging Prometheus's 15s scrape interval would just be
    # noise); each block routes into whichever loggers are configured
    # globally (`journald` -- and implicitly `default`, since Caddy always
    # runs the default logger unless a site opts out of it).
    logLine = "log\n            ";

    # Shared encoder for BOTH global loggers (default file logger via
    # `logFormat`, named `journald` logger in globalConfig): plain JSON
    # wrapped in Caddy's `filter` encoder so sensitive header values
    # never reach disk or the journal in the first place (filtering at
    # the encoder beats filtering downstream -- VictoriaLogs and the
    # rolled files would otherwise retain them). Request Authorization/
    # Proxy-Authorization/Cookie and response Set-Cookie carry
    # credentials and session tokens; the response Location header is
    # dropped because redirect targets routinely embed OAuth
    # authorization codes and signed tokens (e.g. the Pocket ID flows
    # behind auth.jeiang.dev).
    logEncoder = ''
      format filter {
        wrap json
        fields {
          request>headers>Authorization delete
          request>headers>Proxy-Authorization delete
          request>headers>Cookie delete
          resp_headers>Set-Cookie delete
          resp_headers>Location delete
        }
      }
    '';
  in {
    options.edge.crowdsec.enable =
      lib.mkEnableOption ''
        the CrowdSec bouncer HTTP + AppSec handlers on the edge, and (shared
        switch, modules/nixos/crowdsec/default.nix) the CrowdSec engine
        itself. On by default; the sops secrets it and the Caddy wiring need
        (caddy/crowdsec-lapi-url, caddy/crowdsec-lapi-key,
        crowdsec/bouncer-netbird-proxy-key,
        crowdsec/bouncer-legion-node2-firewall) must be present in the
        caddy secrets shard or activation fails. Toggle off to deploy the
        edge without CrowdSec
      ''
      // {default = true;};

    config = {
      services.caddy = {
        enable = true;
        package = self.packages.${system}.caddy;

        # Default (unnamed) logger: this is CrowdSec's acquisition source
        # of truth, not a general access log -- modules/nixos/crowdsec/default.nix
        # tails this exact file path (`services.caddy.logDir`/access.log)
        # via a `source = "file"` acquisition, which needs a stable
        # filesystem path rather than journal fields. It does NOT double
        # as "the" access log for every site block: Caddy access logging
        # is opt-in per site block (see the bare `log` line added to each
        # public site block below), and the named `journald` logger in
        # globalConfig below is what actually feeds those records (plus
        # runtime logs) to VictoriaLogs via the fleet's systemd-journal-upload.
        # Retention here is intentionally short: VictoriaLogs is now the
        # searchable month-long archive, so this file only needs to cover
        # CrowdSec's live tail plus a little local debugging headroom, not
        # long-term storage.
        logFormat = ''
          level INFO
          output file ${config.services.caddy.logDir}/access.log {
            roll_size 100mb
            roll_keep 2
            roll_keep_for 48h
          }
          ${logEncoder}
        '';

        globalConfig = ''
          # Second named logger: everything (runtime + every site's access
          # log once `log` is added to that site block below) to stderr,
          # which systemd captures into the journal, which the fleet's
          # existing systemd-journal-upload ships to legion-node3's
          # VictoriaLogs (modules/hosts/legion/default.nix
          # `services.journald.upload`). No `include`/`exclude` filter on
          # this logger -- deliberate, so both runtime and access records
          # land in VictoriaLogs unfiltered; the file logger above stays
          # the narrower CrowdSec-only source.
          log journald {
            output stderr
            ${logEncoder}
            level INFO
          }

          # The top-level `metrics` global option turns on Prometheus
          # metrics collection for every HTTP
          # server config below (the older `servers { metrics }` nested
          # form is deprecated as of the pinned caddy 2.11.4 -- confirmed
          # via `caddy adapt`'s own warning). Deliberately NOT exposed by
          # binding the `admin` API off localhost (a prior version of this
          # module did that): the admin API is unauthenticated
          # config-mutation surface (POST /load reconfigures the whole
          # edge, /stop shuts it down, etc), and "private network" here
          # means every Legion node (trustedInterfaces enp7s0) -- a single
          # compromised node would be able to rewrite this edge's entire
          # routing table. The admin API stays at the module default
          # (127.0.0.1:2019, unreachable cross-node); metrics are served
          # from the plain HTTP site block below instead, which exposes
          # only the metrics output, nothing administrative.
          metrics

          # Cloudflare sits in front of every orange-clouded hostname here, so
          # without this Caddy treats Cloudflare's edge as the client: every
          # access record carries a Cloudflare IP as `client_ip`, and every
          # CrowdSec decision derived from one bans a Cloudflare PoP rather
          # than the actual client.
          #
          # That is not merely useless, it is an outage: a single probe from
          # one attacker (observed: an Amazonbot `/media../.env` request to
          # auth.jeiang.dev tripping crowdsecurity/appsec-vpatch) bans a shared
          # Cloudflare address, which then 403s every unrelated visitor routed
          # through that PoP, across every proxied hostname. It is what made
          # the binary cache unreachable from GitHub Actions -- `nix` logged
          # `unable to download '.../nix-cache-info': HTTP error 403` and fell
          # back to building from source on every CI run.
          #
          # Both decision paths honour this once set: the bouncer resolves the
          # client through Caddy's own ClientIPVarKey
          # (caddy-crowdsec-bouncer internal/httputils, "the client IP
          # reported here is the actual client IP"), and the hub's
          # crowdsecurity/caddy-logs parser reads
          # `evt.Unmarshaled.caddy.request.client_ip`.
          #
          # The range list comes from the `cloudflare` ip_source module
          # (github.com/WeidiDeng/caddy-cloudflare-ip, modules/packages/caddy.nix)
          # rather than a static list in Nix, so a Cloudflare range change does
          # not silently reintroduce this by going stale.
          servers {
            trusted_proxies cloudflare {
              interval 12h
              timeout 15s
            }
            client_ip_headers Cf-Connecting-Ip
          }

          ${lib.optionalString cfg.crowdsec.enable ''
            # Handler ordering: neither the `crowdsec` nor `appsec` HTTP
            # handler directive registers a position in Caddy's default
            # directive order (both call only
            # httpcaddyfile.RegisterHandlerDirective, never
            # RegisterDirectiveOrder -- verified against
            # github.com/hslatman/caddy-crowdsec-bouncer http/http.go and
            # appsec/appsec.go @v0.13.1), so every site block below that
            # uses them bare (not wrapped in an explicit `route`) needs
            # this global placement: crowdsec's cheap IP-decision check
            # runs before every other directive in its site block, appsec's
            # deeper request inspection right after it.
            order crowdsec first
            order appsec after crowdsec

            # Fail-open posture: enable_hard_fails stays off (default) so
            # Caddy still starts
            # if the LAPI is unreachable, and appsec_fail_open ignores
            # AppSec connection errors instead of blocking traffic.
            crowdsec {
              # `{$VAR}` (not `{env.VAR}`): the crowdsec app parses this
              # field eagerly at config-adapt time instead of through a
              # placeholder replacer, so it needs Caddyfile's textual
              # env-var substitution, confirmed by `caddy validate`
              # rejecting `{env.VAR}` here with an invalid-URL error.
              api_url {$CROWDSEC_LAPI_URL}
              api_key {$CROWDSEC_LAPI_KEY}
              appsec_url http://127.0.0.1:7422
              appsec_fail_open
            }
          ''}
        '';

        extraConfig = ''
          # --- Prometheus metrics, private network only ------------------
          # Port 2020, deliberately NOT 2019: Caddy's admin API keeps
          # listening at its module default (127.0.0.1:2019) since it's no
          # longer reconfigured above, and site blocks sharing a port are
          # merged by Caddy into one listener bound to every interface
          # (`:<port>`, host-matched by route, not IP-bound) -- reusing
          # 2019 here would collide with the admin API's own listener at
          # startup. Plain `http://` scheme forces this listener to skip
          # automatic HTTPS/ACME entirely (no cert to manage for an
          # internal, private-network-only endpoint). Reachability: same
          # pattern as every other cross-node backend in this repo, never
          # opened on the public interface or added to this node's public
          # firewall allowlist (modules/hosts/legion/_service-inventory.nix
          # `caddy` entry, port 2020, "private" scope). Serves only the
          # `metrics` handler -- no admin/config-mutation surface, unlike
          # binding the `admin` API off localhost would (see the `servers
          # { metrics }` comment above).
          http://${node1}:2020 {
            metrics /metrics
          }

          # --- jeiang.dev + *.jeiang.dev: one DNS-01 wildcard cert -------
          # Every other jeiang.dev site block below has no explicit `tls`
          # directive: Caddy 2.10+
          # reuses this already-managed wildcard for them instead of
          # requesting a second certificate per hostname (see
          # https://caddyserver.com/docs/automatic-https#wildcard-certificates).
          jeiang.dev, *.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }

            @apex host jeiang.dev
            handle @apex {
              root * ${website}
              file_server
            }

            # Anything else under the wildcard that isn't one of the
            # specific host blocks below is a stray/typo subdomain.
            handle {
              respond 404
            }
          }

          # aidanpinard.co / pinard.co.tt: separate DNS-01 certs
          # (Cloudflare-hosted zones, not part of the jeiang.dev wildcard
          # SAN).
          aidanpinard.co {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }
            root * ${website}
            file_server
          }

          pinard.co.tt {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }
            root * ${website}
            file_server
          }

          # --- noelejoshua.com: jkmn-website, new input -------------------
          # noelejoshua.com is not in Cloudflare DNS: no explicit `tls`
          # directive, so this falls back to Caddy's standard automatic
          # HTTPS (HTTP-01/TLS-ALPN-01), per the TLS strategy section.
          noelejoshua.com {
            ${logLine}${crowdsecLine}${appsecLine}root * ${portfolio}
            file_server
          }

          # --- auth.jeiang.dev: Pocket ID ---------------------------------
          # Port 1411 is Pocket ID's default listen port.
          auth.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node2}:1411
          }

          # --- cache.jeiang.dev: garret Puller ----------------------------
          # The public substituter (docs/adr/0013). Port 8081 matches
          # modules/nixos/garret/default.nix's puller `listen`.
          #
          # Short timeouts are fine here, unlike the push route below: a
          # NAR request answers 302 to a presigned S3 URL rather than
          # streaming the body, so nothing large ever crosses this proxy --
          # only narinfo and the redirect itself. crowdsec (IP-decision
          # check) applies -- it's cheap, and the engine's own
          # cache-whitelist parser (modules/nixos/crowdsec/default.nix)
          # already keeps bursty cache traffic from generating bad-IP
          # decisions in the first place. appsec is deliberately skipped:
          # cache clients fetch in legitimate high-volume bursts, and
          # skipping the deep-inspection handler on the cache routes is the
          # fail-open-friendly choice for a single-node edge.
          #
          # Grey-clouded in Cloudflare, like the push hostname below but by
          # choice rather than necessity: with NARs served as S3 redirects
          # there is nothing worth proxying except narinfo, and staying off
          # the proxy keeps the cache clear of the shared-PoP ban behaviour
          # that made it unreachable from CI (docs/adr/0013).
          cache.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node4}:8081
          }

          # --- cache-push.jeiang.dev: garret Pusher -----------------------
          # OIDC-authenticated pushes. Port 8082 matches
          # modules/nixos/garret/default.nix's pusher `listen`.
          #
          # This hostname MUST stay grey-clouded/DNS-only in Cloudflare: a
          # push is one streaming PUT of a whole zstd-compressed NAR
          # (garret spec 01-push-protocol) and Cloudflare 413s bodies over
          # 100 MB on the free plan. Long timeouts (>= 15m) for those
          # whole-NAR uploads.
          cache-push.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node4}:8082 {
              transport http {
                read_timeout 15m
                write_timeout 15m
                response_header_timeout 15m
              }
            }
          }

          # --- budget.jeiang.dev: Actual Budget ---------------------------
          # Port 5006 matches Actual Budget's configured listen port
          # (modules/nixos/actual-budget.nix).
          budget.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node4}:5006
          }

          # --- grafana.jeiang.dev: monitoring stack -----------------------
          # Port 3000 is Grafana's default listen port.
          grafana.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node3}:3000
          }

          # --- status.jeiang.dev: Gatus status page -----------------------
          # Port 8086 matches modules/nixos/gatus.nix's `web.port` (not
          # Gatus' own 8080 default, which netbird-relay already holds on
          # legion-node2).
          #
          # Public and ungated, deliberately: this is the page people load
          # when something is broken, and Pocket ID is one of the services
          # it reports on, so putting it behind SSO would take the outage
          # report down with the outage. `appsec` is skipped for the same
          # fail-open reasoning as the cache routes above -- a status page
          # that 403s under load is worse than no status page -- while
          # `crowdsec`'s cheap IP-decision check still applies.
          status.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node2}:8086
          }

          # --- netbird.jeiang.dev: NetBird server/relay -------------------
          # Route split: gRPC/h2c for signal + management + proxy
          # registration, plain REST for api/oauth2 + the
          # dashboard<->management WebSocket, a separate port for the
          # relay WebSocket, and the dashboard static assets as the
          # default fallback. Long read timeouts for the streaming routes.
          netbird.jeiang.dev {
            # crowdsec (IP-decision check, cheap, no body/stream buffering)
            # applies to the whole site including the gRPC/WebSocket
            # routes below. appsec (deep request inspection) is placed
            # only in the fallback dashboard handle at the bottom, not in
            # @grpc/@backend/@relay: those are NetBird's long-lived
            # streams, and modules/nixos/crowdsec/default.nix's local
            # jeiang/appsec-caddy config already carries an on_match
            # allow-rule for these same paths as a second layer -- skipping
            # the handler here avoids paying for AppSec inspection on
            # streaming traffic it would just allow anyway.
            ${logLine}${crowdsecLine}@grpc path /signalexchange.SignalExchange/* /management.ManagementService/* /management.ProxyService/*
            handle @grpc {
              reverse_proxy h2c://${node2}:80
            }

            @backend path /api/* /oauth2/* /ws-proxy/*
            handle @backend {
              reverse_proxy ${node2}:80 {
                transport http {
                  read_timeout 15m
                }
              }
            }

            # Relay port from the inventory (legion-node2 netbird-relay).
            @relay path /relay*
            handle @relay {
              reverse_proxy ${node2}:8080 {
                transport http {
                  read_timeout 15m
                }
              }
            }

            # The browser RDP client's IronRDP WASM bundle, which the
            # nixpkgs-built dashboard above does not carry -- see
            # modules/packages/netbird-ironrdp.nix for why. Must precede the
            # fallback `handle`: without it these two paths fall through to
            # `try_files`' final `/index.html` candidate, so the dashboard's
            # `import("/ironrdp-pkg/ironrdp_web.js")` gets an HTML document,
            # fails to parse as an ES module, and every RDP session dies with
            # "IronRDP module not loaded". handle_path (not handle) because
            # the release assets sit at the package's top level, so the
            # `/ironrdp-pkg` prefix has to come off before the file lookup.
            handle_path /ironrdp-pkg/* {
              ${appsecLine}root * ${netbirdIronRDP}
              file_server
            }

            # The dashboard (netbird-dashboard 2.x) is a Next.js `output:
            # "export"` static build: every route is pre-rendered to its own
            # top-level file (`networks.html`, `peers.html`, ...), not a
            # single-page app served from one index.html. So a direct hit on
            # `/networks` must resolve to `networks.html`; the `{path}.html`
            # candidate is what does that. Without it, `try_files` skips the
            # `networks/` dir (RSC `.txt` payloads, no HTML index) and falls
            # straight through to `/index.html` -- serving the home page's
            # document at the /networks URL, which makes Next's App Router
            # hydrate with the wrong route tree and hard-reload forever (the
            # deep-link "loading loop"; client-side nav works because it
            # fetches the `.txt` RSC payloads directly). This mirrors
            # NetBird's own reference nginx config's
            # `try_files $uri $uri.html $uri/ =404` (dashboard
            # docker/default.conf); the final `/index.html` keeps the
            # SPA-style fallback for anything unmatched.
            handle {
              ${appsecLine}root * ${netbirdDashboard}
              try_files {path} {path}.html {path}/index.html /index.html
              file_server
            }
          }

          # --- bill-split.jeiang.dev: bill-splitter -----------------------
          # jeiang/bill-splitter's flake now builds a static site to
          # $out/dist (verified via `nix flake show`/`nix build`), so it's
          # served the same way as the other static sites above.
          bill-split.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}root * ${billSplitter}
            file_server
          }

          # --- rivals.jeiang.dev: character-randomizer --------------------
          # jeiang/character-randomizer builds a static site to $out,
          # served the same way as the other static sites above.
          rivals.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}root * ${rivalsRandomizer}
            file_server
          }

          # --- github.jeiang.dev: redirect --------------------------------
          github.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}redir https://github.com/jeiang{uri} 301
          }

          # --- jellyfin.plyrex.dev / seerr.plyrex.dev: placeholders -------
          # jellyfin/seerr have a deferred Tailscale backend. 503 rather
          # than 200: accurately signals "temporarily unavailable" instead
          # of looking like real content that a client or proxy might
          # cache. Not in Cloudflare DNS, so (like noelejoshua.com) these fall
          # back to standard automatic HTTPS.
          jellyfin.plyrex.dev, seerr.plyrex.dev {
            ${logLine}${crowdsecLine}${appsecLine}respond "Service migrating. This service is temporarily unavailable while it moves to new infrastructure." 503
          }
        '';
      };

      # Cloudflare DNS API token for the DNS-01 issuer above, from the caddy
      # secrets shard.
      sops.secrets = let
        sopsFile = ./secrets.yaml;
      in
        {
          "caddy/cloudflare-dns-token" = {inherit sopsFile;};
        }
        // lib.optionalAttrs cfg.crowdsec.enable {
          "caddy/crowdsec-lapi-url" = {inherit sopsFile;};
          "caddy/crowdsec-lapi-key" = {inherit sopsFile;};
        };

      sops.templates."caddy.env" = {
        owner = config.services.caddy.user;
        group = config.services.caddy.group;
        # An EnvironmentFile is read once at start-up, and a deploy that
        # only rotates a secret leaves the unit definition byte-identical
        # -- so without this Caddy keeps using the pre-rotation token/key.
        # Same reasoning as modules/nixos/garret/default.nix's templates.
        restartUnits = ["caddy.service"];
        content =
          "CLOUDFLARE_API_TOKEN=${config.sops.placeholder."caddy/cloudflare-dns-token"}\n"
          + lib.optionalString cfg.crowdsec.enable ''
            CROWDSEC_LAPI_URL=${config.sops.placeholder."caddy/crowdsec-lapi-url"}
            CROWDSEC_LAPI_KEY=${config.sops.placeholder."caddy/crowdsec-lapi-key"}
          '';
      };
      services = {
        caddy.environmentFile = config.sops.templates."caddy.env".path;

        netbird.server.dashboard = {
          enable = true;
          managementServer = "https://netbird.jeiang.dev";
          settings = {
            AUTH_AUDIENCE = "netbird-dashboard";
            AUTH_CLIENT_ID = "netbird-dashboard";
            AUTH_AUTHORITY = "https://netbird.jeiang.dev/oauth2";
            AUTH_SUPPORTED_SCOPES = "openid profile email groups";
            AUTH_REDIRECT_URI = "/nb-auth";
            AUTH_SILENT_REDIRECT_URI = "/nb-silent-auth";
            USE_AUTH0 = false;
          };
        };
      };

      systemd.services.caddy.serviceConfig.MemoryMax = "256M";

      # 80/443 tcp public are already opened for legion-node1 by the
      # `caddy` entry in modules/hosts/legion/_service-inventory.nix (via
      # firewallPortsFor in modules/hosts/legion/default.nix); no change
      # needed here.
    };
  };
}
