{self, ...}: {
  # docs/MIGRATION.md piece 1.1: Edge Node Caddy. Imported only for the
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
  in {
    options.edge.crowdsec.enable = lib.mkEnableOption ''
      the CrowdSec bouncer HTTP + AppSec handlers on the edge. Off by
      default so the edge works before piece 1.3 stands up the LAPI.
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
                  # 3.2) terminates TLS itself.
                  proxy tcp/${node2}:443
                }
              }
              tls
            }
          }

          ${lib.optionalString cfg.crowdsec.enable ''
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
          # Site content (the website/jkmn-website static roots) lands in
          # piece 1.2; for now every host under the wildcard just proves
          # out DNS-01 issuance.
          jeiang.dev, *.jeiang.dev {
            tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
            }

            respond 404
          }

          # aidanpinard.co / pinard.co.tt: separate DNS-01 certs per
          # docs/MIGRATION.md (Hetzner-hosted zones, not part of the
          # jeiang.dev wildcard SAN). Content lands in piece 1.2.
          aidanpinard.co {
            tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
            }
            respond 404
          }

          pinard.co.tt {
            tls {
              dns hetzner {env.HETZNER_DNS_TOKEN}
            }
            respond 404
          }

          # --- auth.jeiang.dev: Pocket ID (piece 4.1) ---------------------
          # Port 1411 matches the deployed pocket-id image's listen port
          # (k8s-manifests idp/values.yaml `pocketId.port`).
          auth.jeiang.dev {
            reverse_proxy ${node2}:1411
          }

          # --- attic.jeiang.dev: Attic (piece 5.1) ------------------------
          # Long timeouts for NAR uploads (docs/MIGRATION.md, >= 15m).
          # Port 8080 matches k8s-manifests attic/values.yaml `server.port`.
          attic.jeiang.dev {
            reverse_proxy ${node4}:8080 {
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
            reverse_proxy ${node4}:5006
          }

          # --- grafana.jeiang.dev: monitoring stack (piece 6.1) -----------
          # Port 3000 is Grafana's default listen port.
          grafana.jeiang.dev {
            reverse_proxy ${node3}:3000
          }

          # --- netbird.jeiang.dev: NetBird server/relay (piece 3.1) -------
          # Route split mirrors the live k8s-manifests
          # netbird/templates/ingress.yaml: gRPC/h2c for signal +
          # management + proxy registration, plain REST for api/oauth2 +
          # the dashboard<->management WebSocket, and a separate port for
          # the relay WebSocket. Long read timeouts for the streaming
          # routes. The dashboard static-asset fallback lands in piece 1.2.
          netbird.jeiang.dev {
            @grpc path /signalexchange.SignalExchange/* /management.ManagementService/* /management.ProxyService/*
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

            # Default fallback (dashboard static assets) lands in piece 1.2.
            handle {
              respond 404
            }
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
