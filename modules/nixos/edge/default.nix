{
  self,
  inputs,
  ...
}: {
  # docs/MIGRATION.md piece 1.1/1.2: Edge Node Caddy. Imported only for the
  # inventory's edge node (modules/hosts/legion/default.nix), alongside K3s
  # until the runbook (piece 1.5) cuts DNS over.
  flake.nixosModules.edge = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.edge;
    system = pkgs.stdenv.hostPlatform.system;

    # Legion private-network addresses (modules/hosts/legion/default.nix
    # `legionNodes`); backends below don't exist yet (later phases), so
    # these routes may 502 until their service lands.
    node2 = "172.17.0.2"; # NetBird server/relay (3.1), Pocket ID (4.1)
    node3 = "172.17.0.3"; # Monitoring/Grafana (6.1)
    node4 = "172.17.0.4"; # Attic (5.1), Actual Budget (5.2)

    website = inputs.website.packages.${system}.default;
    portfolio = "${inputs.portfolio.packages.${system}.default}/dist";
    billSplitter = "${inputs.bill-splitter.packages.${system}.default}/dist";
    netbirdDashboard = self.packages.${system}.netbird-dashboard;

    # Bare `crowdsec`/`appsec` HTTP handler directives (below, gated on
    # cfg.crowdsec.enable so a disabled toggle renders byte-identical
    # output to before this existed). Each already carries its own
    # trailing newline + indent so callers just concatenate them ahead of
    # the site block's first real directive.
    crowdsecLine = lib.optionalString cfg.crowdsec.enable "crowdsec\n            ";
    appsecLine = lib.optionalString cfg.crowdsec.enable "appsec\n            ";
  in {
    options.edge.crowdsec.enable = lib.mkEnableOption ''
      the CrowdSec bouncer HTTP + AppSec handlers on the edge, and (shared
      switch, modules/nixos/crowdsec/default.nix) the CrowdSec engine
      itself. Off by default: piece 1.3's engine module cleanly evaluates,
      but the sops secrets it and this option's Caddy wiring both need
      (caddy/crowdsec-lapi-url, caddy/crowdsec-lapi-key,
      crowdsec/bouncer-netbird-proxy-key) are not yet in
      modules/nixos/sops/secrets.yaml, so activation would fail. Flip once
      those exist (docs/runbooks/edge-cutover.md CrowdSec enablement step).
    '';

    config = {
      services.caddy = {
        enable = true;
        package = self.packages.${system}.caddy;

        # Default logger doubles as the access log for every site block
        # below (Caddy uses a custom logger named "default" for both
        # purposes). JSON file, not journald: piece 1.3's CrowdSec log
        # acquisition reads a stable file path instead of mapping journal
        # fields.
        logFormat = ''
          level INFO
          output file ${config.services.caddy.logDir}/access.log {
            roll_size 100mb
            roll_keep 10
          }
          format json
        '';

        globalConfig = ''
          # caddy-l4 + the HTTP app both wanting :443 is exactly the case
          # covered by caddy-l4's own "combining apps" example
          # (github.com/mholt/caddy-l4/blob/master/docs/examples/combining_apps.md):
          # giving layer4 its own :443 listener conflicts with the HTTP
          # app's :443 listener, so instead `layer4` is registered as a
          # *listener wrapper* on the HTTP app's :443 server, ahead of the
          # `tls` wrapper. A connection matching the NetBird proxy SNI is
          # proxied as raw bytes and never reaches the `tls` wrapper (no
          # local termination); everything else falls through to `tls`
          # and is handled by the ordinary site blocks below. Port 80 is
          # untouched (plain HTTP app listener) for redirects/HTTP-01.
          servers :443 {
            listener_wrappers {
              layer4 {
                @netbird_proxy tls sni proxy.jeiang.dev *.proxy.jeiang.dev
                route @netbird_proxy {
                  # RAW passthrough: legion-node2's netbird-proxy (piece
                  # 3.2) terminates TLS itself. Without proxy_protocol
                  # below, the RP's CrowdSec bouncer would see every
                  # passthrough client as this edge node's private IP
                  # (flagged in piece 3.2's report) and could ban the
                  # edge outright, blocking all passthrough traffic.
                  #
                  # v2 is the JSON field caddy-l4 v0.1.2's l4proxy.Handler
                  # exposes (modules/l4proxy/proxy.go `ProxyProtocol
                  # string json:"proxy_protocol"`, Caddyfile sub-directive
                  # `proxy_protocol <v1|v2>`, verified against the
                  # mholt/caddy-l4@v0.1.2 tag pinned in
                  # modules/packages/caddy.nix). This MUST be enabled on
                  # BOTH ends -- here and NB_PROXY_PROXY_PROTOCOL in
                  # modules/nixos/netbird-server/proxy.nix -- or the TLS
                  # stream breaks: one side prepending a PROXY v2 header
                  # the other side doesn't expect is read as garbage
                  # ClientHello bytes.
                  proxy tcp/${node2}:443 {
                    proxy_protocol v2
                  }
                }
              }
              tls
            }
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

            # Fail-open posture (docs/MIGRATION.md Confirmed Decisions):
            # enable_hard_fails stays off (default) so Caddy still starts
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
          # --- jeiang.dev + *.jeiang.dev: one DNS-01 wildcard cert -------
          # (docs/MIGRATION.md TLS strategy). Every other jeiang.dev site
          # block below has no explicit `tls` directive: Caddy 2.10+
          # reuses this already-managed wildcard for them instead of
          # requesting a second certificate per hostname (see
          # https://caddyserver.com/docs/automatic-https#wildcard-certificates).
          jeiang.dev, *.jeiang.dev {
            ${crowdsecLine}${appsecLine}tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
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

          # aidanpinard.co / pinard.co.tt: separate DNS-01 certs per
          # docs/MIGRATION.md (Hetzner-hosted zones, not part of the
          # jeiang.dev wildcard SAN).
          aidanpinard.co {
            ${crowdsecLine}${appsecLine}tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
            }
            root * ${website}
            file_server
          }

          pinard.co.tt {
            ${crowdsecLine}${appsecLine}tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
            }
            root * ${website}
            file_server
          }

          # --- noelejoshua.com: jkmn-website (piece 1.2), new input -------
          # noelejoshua.com is not in Hetzner DNS: no explicit `tls`
          # directive, so this falls back to Caddy's standard automatic
          # HTTPS (HTTP-01/TLS-ALPN-01), per the TLS strategy section.
          noelejoshua.com {
            ${crowdsecLine}${appsecLine}root * ${portfolio}
            file_server
          }

          # --- auth.jeiang.dev: Pocket ID (piece 4.1) ---------------------
          # Port 1411 matches the deployed pocket-id image's listen port
          # (k8s-manifests idp/values.yaml `pocketId.port`).
          auth.jeiang.dev {
            ${crowdsecLine}${appsecLine}reverse_proxy ${node2}:1411
          }

          # --- attic.jeiang.dev: Attic (piece 5.1) ------------------------
          # Long timeouts for NAR uploads (docs/MIGRATION.md, >= 15m).
          # Port 8080 matches k8s-manifests attic/values.yaml `server.port`.
          # crowdsec (IP-decision check) applies -- it's cheap and the
          # engine's own attic-cache-whitelist parser
          # (modules/nixos/crowdsec/default.nix) already keeps bursty NAR
          # traffic from generating bad-IP decisions in the first place.
          # appsec is deliberately skipped here: the k8s-manifests Traefik
          # deployment ran AppSec globally on every route including this
          # one, but its own README documents Attic NAR uploads as
          # legitimate high-volume bursts that need a whitelist to avoid
          # false positives -- skipping the deep-inspection handler on this
          # route entirely is the Caddyfile-level equivalent for a
          # single-node fail-open edge, avoiding both the false-positive
          # risk and the cost of body inspection on large NAR blobs.
          attic.jeiang.dev {
            ${crowdsecLine}reverse_proxy ${node4}:8080 {
              transport http {
                read_timeout 15m
                write_timeout 15m
                response_header_timeout 15m
              }
            }
          }

          # --- budget.jeiang.dev: Actual Budget (piece 5.2) ---------------
          # Port 5006 matches k8s-manifests actual-budget/values.yaml
          # `service.port`.
          budget.jeiang.dev {
            ${crowdsecLine}${appsecLine}reverse_proxy ${node4}:5006
          }

          # --- grafana.jeiang.dev: monitoring stack (piece 6.1) -----------
          # Port 3000 is Grafana's default listen port.
          grafana.jeiang.dev {
            ${crowdsecLine}${appsecLine}reverse_proxy ${node3}:3000
          }

          # --- netbird.jeiang.dev: NetBird server/relay (piece 3.1) -------
          # Route split mirrors the live k8s-manifests
          # netbird/templates/ingress.yaml: gRPC/h2c for signal +
          # management + proxy registration, plain REST for api/oauth2 +
          # the dashboard<->management WebSocket, a separate port for the
          # relay WebSocket, and the dashboard static assets (piece 1.2)
          # as the default fallback. Long read timeouts for the streaming
          # routes.
          netbird.jeiang.dev {
            # crowdsec (IP-decision check, cheap, no body/stream buffering)
            # applies to the whole site including the gRPC/WebSocket
            # routes below. appsec (deep request inspection) is placed
            # only in the fallback dashboard handle at the bottom, not in
            # @grpc/@backend/@relay: those are NetBird's long-lived
            # streams (docs/MIGRATION.md piece 1.3 exclusion), and
            # modules/nixos/crowdsec/default.nix's local
            # jeiang/appsec-caddy config already carries an on_match
            # allow-rule for these same paths as a second layer -- skipping
            # the handler here avoids paying for AppSec inspection on
            # streaming traffic it would just allow anyway.
            ${crowdsecLine}@grpc path /signalexchange.SignalExchange/* /management.ManagementService/* /management.ProxyService/*
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

            handle {
              ${appsecLine}root * ${netbirdDashboard}
              file_server
            }
          }

          # --- bill-split.jeiang.dev: bill-splitter (piece 1.2) -----------
          # jeiang/bill-splitter's flake now builds a static site to
          # $out/dist (verified via `nix flake show`/`nix build`), so it's
          # served the same way as the other static sites above.
          bill-split.jeiang.dev {
            ${crowdsecLine}${appsecLine}root * ${billSplitter}
            file_server
          }

          # --- github.jeiang.dev: redirect --------------------------------
          github.jeiang.dev {
            ${crowdsecLine}${appsecLine}redir https://github.com/jeiang{uri} 301
          }

          # --- jellyfin.plyrex.dev / seerr.plyrex.dev: placeholders -------
          # (piece 1.4, deferred). 503 rather than 200: accurately signals
          # "temporarily unavailable" instead of looking like real content
          # that a client or proxy might cache. Not in Hetzner DNS, so
          # (like noelejoshua.com) these fall back to standard automatic
          # HTTPS.
          jellyfin.plyrex.dev, seerr.plyrex.dev {
            ${crowdsecLine}${appsecLine}respond "Service migrating. This service is temporarily unavailable while it moves to new infrastructure." 503
          }
        '';
      };

      # Hetzner DNS API token for the DNS-01 issuer above. The key doesn't
      # exist in modules/nixos/sops/secrets.yaml yet: run `just sops-edit`
      # and add a `caddy: hetzner-dns-token: <token>` entry before first
      # deploying the edge node (sops-nix only checks this at activation
      # time, not eval time, so it's safe to land the module first).
      sops.secrets =
        {
          "caddy/hetzner-dns-token" = {};
        }
        // lib.optionalAttrs cfg.crowdsec.enable {
          "caddy/crowdsec-lapi-url" = {};
          "caddy/crowdsec-lapi-key" = {};
        };

      sops.templates."caddy.env" = {
        owner = config.services.caddy.user;
        group = config.services.caddy.group;
        content =
          "HETZNER_DNS_TOKEN=${config.sops.placeholder."caddy/hetzner-dns-token"}\n"
          + lib.optionalString cfg.crowdsec.enable ''
            CROWDSEC_LAPI_URL=${config.sops.placeholder."caddy/crowdsec-lapi-url"}
            CROWDSEC_LAPI_KEY=${config.sops.placeholder."caddy/crowdsec-lapi-key"}
          '';
      };
      services.caddy.environmentFile = config.sops.templates."caddy.env".path;

      # 80/443 tcp public are already opened for legion-node1 by the
      # `caddy` entry in modules/hosts/legion/_service-inventory.nix (via
      # firewallPortsFor in modules/hosts/legion/default.nix); no change
      # needed here.
    };
  };
}
