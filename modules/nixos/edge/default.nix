{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.edge = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.edge;
    system = pkgs.stdenv.hostPlatform.system;

    node1 = self.lib.legionNodes.legion-node1.privateIPv4;
    node2 = self.lib.legionNodes.legion-node2.privateIPv4;
    node3 = self.lib.legionNodes.legion-node3.privateIPv4;
    node4 = self.lib.legionNodes.legion-node4.privateIPv4;

    ports = self.lib.ports;
    port = node: service: toString ports.${node}.${service};

    website = inputs.website.packages.${system}.default;
    portfolio = "${inputs.portfolio.packages.${system}.default}/dist";
    billSplitter = "${inputs.bill-splitter.packages.${system}.default}/dist";
    rivalsRandomizer = inputs.character-randomizer.packages.${system}.default;
    mdTableEditor = inputs.markdown-table-live-editor.packages.${system}.default;
    netbirdDashboard = config.services.netbird.server.dashboard.finalDrv;
    netbirdIronRDP = self.packages.${system}.netbird-ironrdp-web;

    # Each carries its own trailing newline + indent; callers concatenate
    # them ahead of a site block's first real directive.
    crowdsecLine = lib.optionalString cfg.crowdsec.enable "crowdsec\n            ";
    appsecLine = lib.optionalString cfg.crowdsec.enable "appsec\n            ";

    # Only forced inside the cfg.anubis.enable branch of mkContentSite --
    # with the module unimported, services.anubis.instances is empty and
    # this would throw.
    anubisSocket = config.services.anubis.instances.content.settings.BIND;

    # Exemptions are enforced here in Caddy (first matching handle wins),
    # not as Anubis ALLOW rules: non-browser clients -- ACME HTTP-01
    # validation, crawler metadata, feed readers -- can never solve a
    # proof-of-work challenge.
    mkContentSite = root:
      if cfg.anubis.enable
      then ''
        @unchallenged path /.well-known/* /robots.txt /sitemap.xml /favicon.ico /feed.xml /rss.xml /atom.xml
        handle @unchallenged {
          root * ${root}
          file_server
        }

        handle {
          reverse_proxy unix/${anubisSocket} {
            # Anubis keys its challenge state on X-Real-Ip; {client_ip} is
            # the Cloudflare-aware placeholder, not {remote_host}.
            header_up X-Real-Ip {client_ip}
          }
        }
      ''
      else ''
        root * ${root}
        file_server
      '';

    # Caddy access logging is opt-in per site block: without a `log`
    # directive a site emits zero access records.
    logLine = "log\n            ";

    # Shared by both global loggers: strip credential-bearing headers at the
    # encoder so they never reach disk or the journal; Location routinely
    # embeds OAuth authorization codes.
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
    options.edge.anubis = {
      enable = lib.mkEnableOption ''
        the Anubis proof-of-work gate in front of the static content site
        blocks only (jeiang.dev apex, aidanpinard.co, pinard.co.tt,
        noelejoshua.com). Enabled by modules/nixos/anubis.nix, which is
        imported only for the inventory node placing `anubis`
      '';

      originPort = lib.mkOption {
        type = lib.types.port;
        default = 8129;
        description = ''
          Loopback port of the internal Caddy listener that serves the
          protected static roots, and which the Anubis instance proxies
          to as its TARGET. Read by modules/nixos/anubis.nix, so it is a
          real cross-module boundary rather than a one-off constant.

          Must not collide with Caddy's admin API (127.0.0.1:2019) or the
          metrics site block (2020); site blocks sharing a port get merged
          into a single listener, so a collision is a startup failure.
        '';
      };
    };

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

        # CrowdSec's file acquisition tails this exact path; retention is
        # short since VictoriaLogs is the searchable archive.
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
          # Runtime + per-site access records to stderr -> journal ->
          # VictoriaLogs via the fleet's systemd-journal-upload.
          log journald {
            output stderr
            ${logEncoder}
            level INFO
          }

          # The admin API stays loopback-only (unauthenticated config
          # mutation); metrics are served from the :2020 site block instead.
          metrics

          # Without this every client_ip is a Cloudflare PoP address, and a
          # CrowdSec decision bans a shared PoP -- 403ing unrelated visitors
          # across every proxied hostname (observed: CI cache outage).
          servers {
            trusted_proxies cloudflare {
              interval 12h
              timeout 15s
            }
            client_ip_headers Cf-Connecting-Ip
          }

          ${lib.optionalString cfg.crowdsec.enable ''
            # Neither handler registers a default directive order, so bare
            # site-block usage needs this global placement.
            order crowdsec first
            order appsec after crowdsec

            # Fail-open: enable_hard_fails stays off so Caddy starts with
            # the LAPI unreachable; appsec_fail_open ignores AppSec errors.
            crowdsec {
              # {$VAR}, not {env.VAR}: this field is parsed at config-adapt
              # time, before the placeholder replacer runs.
              api_url {$CROWDSEC_LAPI_URL}
              api_key {$CROWDSEC_LAPI_KEY}
              appsec_url http://127.0.0.1:7422
              appsec_fail_open
            }
          ''}
        '';

        extraConfig = ''
          # 2019 would collide with the admin API listener; plain http://
          # skips automatic HTTPS/ACME for this private-network-only block.
          http://${node1}:2020 {
            metrics /metrics
          }

          ${lib.optionalString cfg.anubis.enable ''
            # Ungated view of the protected static roots; loopback-only, so
            # only Anubis on this node can reach it. The respond 404
            # fallback guards the Host-preservation assumption.
            http://127.0.0.1:${toString cfg.anubis.originPort} {
              @website host jeiang.dev aidanpinard.co pinard.co.tt
              handle @website {
                root * ${website}
                file_server
              }

              @portfolio host noelejoshua.com
              handle @portfolio {
                root * ${portfolio}
                file_server
              }

              handle {
                respond 404
              }
            }
          ''}

          # Caddy 2.10+ reuses this DNS-01 wildcard for the other jeiang.dev
          # blocks below -- none of them needs its own tls directive.
          jeiang.dev, *.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }

            @apex host jeiang.dev
            handle @apex {
              ${mkContentSite website}
            }

            handle {
              respond 404
            }
          }

          aidanpinard.co {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }
            ${mkContentSite website}
          }

          pinard.co.tt {
            ${logLine}${crowdsecLine}${appsecLine}tls {
              dns cloudflare {env.CLOUDFLARE_API_TOKEN}
            }
            ${mkContentSite website}
          }

          # Not in Cloudflare DNS: renews via Caddy's standard automatic
          # HTTPS (HTTP-01/TLS-ALPN-01) rather than DNS-01.
          noelejoshua.com {
            ${logLine}${crowdsecLine}${appsecLine}${mkContentSite portfolio}
          }

          # Every site block from here down is deliberately NOT behind the
          # Anubis gate: these are machine-consumed routes, and a
          # proof-of-work interstitial in front of a non-browser client is
          # an outage, not a trade-off.

          auth.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node2}:${port "legion-node2" "pocket-id"}
          }

          # appsec skipped on the cache routes: clients legitimately fetch
          # in high-volume bursts, and fail-open wins here.
          cache.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node4}:${port "legion-node4" "garret-puller"}
          }

          # MUST stay grey-clouded/DNS-only in Cloudflare: a push is one
          # streaming PUT of a whole NAR and Cloudflare 413s bodies over
          # 100 MB on the free plan. Long timeouts for those uploads.
          cache-push.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node4}:${port "legion-node4" "garret-pusher"} {
              transport http {
                read_timeout 15m
                write_timeout 15m
                response_header_timeout 15m
              }
            }
          }

          budget.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node4}:${port "legion-node4" "actual-budget"}
          }

          # basic_auth because Pocket ID exposes no forward-auth endpoint;
          # the bcrypt hash is not a secret. appsec skipped: photo batch
          # uploads are large multipart bursts.
          color-hunt.jeiang.dev {
            ${logLine}${crowdsecLine}basic_auth {
              jeiang $2a$14$5LJ5Rw4wAUPKO8.EN0q6Z.sCiFrjFT0a.h1rSn4xbgD2u7xB9WuLa
            }
            reverse_proxy ${node2}:${port "legion-node2" "color-hunt"}
          }

          grafana.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}reverse_proxy ${node3}:${port "legion-node3" "grafana"}
          }

          # Ungated deliberately: it reports on Pocket ID, so SSO (or
          # netbird-proxy, which authenticates against it) would take the
          # outage report down with the outage. appsec skipped, fail-open.
          status.jeiang.dev {
            ${logLine}${crowdsecLine}reverse_proxy ${node4}:${port "legion-node4" "gatus"}
          }

          netbird.jeiang.dev {
            # appsec only on the dashboard handles below: @grpc/@backend/
            # @relay are long-lived streams the local AppSec config would
            # allow anyway.
            ${logLine}${crowdsecLine}@grpc path /signalexchange.SignalExchange/* /management.ManagementService/* /management.ProxyService/*
            handle @grpc {
              reverse_proxy h2c://${node2}:${port "legion-node2" "netbird-http"}
            }

            @backend path /api/* /oauth2/* /ws-proxy/*
            handle @backend {
              reverse_proxy ${node2}:${port "legion-node2" "netbird-http"} {
                transport http {
                  read_timeout 15m
                }
              }
            }

            @relay path /relay*
            handle @relay {
              reverse_proxy ${node2}:${port "legion-node2" "netbird-relay"} {
                transport http {
                  read_timeout 15m
                }
              }
            }

            # IronRDP WASM bundle the nixpkgs dashboard doesn't carry
            # (modules/packages/netbird-ironrdp.nix). Must precede the
            # fallback handle or the module import gets index.html.
            handle_path /ironrdp-pkg/* {
              ${appsecLine}root * ${netbirdIronRDP}
              file_server
            }

            # Next.js `output: "export"` build: the {path}.html candidate is
            # what makes a direct /networks hit resolve; without it deep
            # links hydrate the wrong route tree and hard-reload forever.
            handle {
              ${appsecLine}root * ${netbirdDashboard}
              try_files {path} {path}.html {path}/index.html /index.html
              file_server
            }
          }

          bill-split.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}root * ${billSplitter}
            file_server
          }

          rivals.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}root * ${rivalsRandomizer}
            file_server
          }

          mdtable.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}root * ${mdTableEditor}
            file_server
          }

          github.jeiang.dev {
            ${logLine}${crowdsecLine}${appsecLine}redir https://github.com/jeiang{uri} 301
          }
        '';
      };

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
    };
  };
}
