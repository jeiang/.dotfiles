{
  self,
  inputs,
  config,
  lib,
  ...
}: let
  legionServices = config.legion.services;
  metricsPort = 2020;
  apex = "jeiang.dev";
  websiteHostnames = [apex "aidanpinard.co" "pinard.co.tt"];
  toolSites =
    lib.mapAttrs (name: title: {
      hostname = "${name}.${apex}";
      inherit title;
    }) {
      bill-split = "Bill Splitter";
      mdtable = "Markdown Table Editor";
      rivals = "Rivals Randomizer";
    };
in {
  flake.lib = {
    inherit websiteHostnames toolSites;
  };

  legion.services.caddy = {
    node = "alda";
    module = "edge";
    units = ["caddy"];
    ports.metrics = metricsPort;
    # ntfy's SSE/WebSocket streams stay off the Cloudflare proxy, and the
    # client IP reaches ntfy's rate limiter.
    publicHostnames = [self.lib.ntfyHostname];
    publicPorts = [
      {
        port = 80;
        proto = "tcp";
      }
      {
        port = 443;
        proto = "tcp";
      }
    ];
  };

  nixos.modules.edge = {
    config,
    lib,
    pkgs,
    ...
  }: let
    host = config.networking.hostName;
    system = pkgs.stdenv.hostPlatform.system;
    upstream = service: port: "${self.lib.serviceAddress host service}:${toString legionServices.${service}.ports.${port}}";
    tinyauth = "127.0.0.1:${toString legionServices.tinyauth.ports.app}";
    atrium = "${self.lib.netbirdPeers.artemis}:${toString self.lib.atriumWebPort}";

    website = inputs.website.packages.${system}.default;

    serveRoot = root: ''
      root * ${root}
      file_server
    '';

    # The portfolio rate-limits logins on the last X-Forwarded-For hop, and
    # Caddy appends the Cloudflare PoP (a trusted proxy) there; overwrite it
    # with the resolved client address instead. Both callers are reached
    # only over https, and the app trusts X-Forwarded-Proto https alone:
    # without it every admin form POST fails Astro's origin check.
    servePortfolio = clientIp: ''
      reverse_proxy ${upstream "portfolio" "app"} {
        header_up X-Forwarded-For ${clientIp}
        header_up X-Forwarded-Proto https
      }
    '';

    # Gatus reaches the content sites over the private network or mesh and
    # cannot solve a challenge. remote_ip is the TCP peer, so a forwarded
    # header cannot claim these sources.
    monitorSources = lib.concatMapStringsSep " " (ip: "${ip}/32") (builtins.filter (ip: ip != null) (map (self.lib.serviceAddress host) self.lib.gatusServices));

    # Exemptions are enforced here (first matching handle wins), not as
    # Anubis ALLOW rules: non-browser clients -- ACME HTTP-01 validation,
    # crawler metadata, feed readers -- can never solve a proof-of-work
    # challenge.
    gate = {
      serve,
      unchallenged ? [],
    }: ''
      @unchallenged path /.well-known/* /robots.txt /sitemap.xml /favicon.ico /feed.xml /rss.xml /atom.xml ${lib.concatStringsSep " " unchallenged}
      handle @unchallenged {
        ${serve}
      }

      @monitor remote_ip ${monitorSources}
      handle @monitor {
        ${serve}
      }

      handle {
        import anubis
      }
    '';

    # Keeps credential-bearing headers off disk and out of the journal;
    # Location routinely embeds OAuth authorization codes.
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

    renderSite = site: ''
      ${lib.concatStringsSep ", " site.hosts} {
        # Access logging is opt-in per site block.
        log
        ${lib.optionalString site.content ''
        encode zstd gzip
        header {
          Strict-Transport-Security "max-age=31536000"
          X-Content-Type-Options nosniff
          Referrer-Policy strict-origin-when-cross-origin
        }
      ''}
        crowdsec
        ${lib.optionalString site.appsec "appsec"}
        ${lib.optionalString site.dnsChallenge ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
        }
      ''}
        ${site.config}
      }
    '';
  in {
    options.edge.sites = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          hosts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [name];
          };
          content = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Browser-facing: compressed, with transport and sniffing headers.";
          };
          appsec = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Run CrowdSec AppSec on the whole site; off for sites that place it per handle or skip it.";
          };
          dnsChallenge = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Issue the certificate over DNS-01 through Cloudflare instead of HTTP-01.";
          };
          config = lib.mkOption {type = lib.types.lines;};
        };
      }));
      default = {};
      description = "Public site blocks of the edge Caddy, all behind the CrowdSec bouncer.";
    };

    config = {
      edge.sites =
        {
          # Caddy 2.10+ reuses this DNS-01 wildcard for the other jeiang.dev
          # sites, so none of them needs its own tls directive.
          ${apex} = {
            hosts = [apex "*.${apex}"];
            content = true;
            dnsChallenge = true;
            config = ''
              @apex host ${apex}
              handle @apex {
                ${gate {serve = serveRoot website;}}
              }

              handle {
                respond 404
              }
            '';
          };
        }
        // lib.genAttrs (lib.remove apex websiteHostnames) (_: {
          content = true;
          dnsChallenge = true;
          config = gate {serve = serveRoot website;};
        })
        // {
          # In its owner's Cloudflare account, proxied, so not in dns/: renews
          # via HTTP-01 rather than DNS-01.
          portfolio = {
            hosts = self.lib.portfolioHostnames;
            content = true;
            config = gate {
              serve = servePortfolio "{client_ip}";
              # The admin API is session-authenticated and throttled by the
              # app; uploads are fetched by crawlers reading og:image.
              unchallenged = ["/api/*" "/healthz" "/uploads/*"];
            };
          };

          # Sites below are deliberately ungated: their clients are machines,
          # for which a proof-of-work interstitial is an outage.

          ${self.lib.pocketIdHostname}.config = "reverse_proxy ${upstream "pocket-id" "app"}";

          ${self.lib.ntfyHostname} = {
            appsec = false;
            config = "reverse_proxy ${upstream "ntfy" "app"}";
          };

          ${self.lib.grafanaHostname}.config = "reverse_proxy ${upstream "monitoring" "grafana"}";

          # Ungated deliberately: it reports on Pocket ID, so SSO (or
          # netbird-proxy, which authenticates against it) would take the
          # outage report down with the outage. appsec skipped, fail-open.
          ${self.lib.statusHostname} = {
            appsec = false;
            config = "reverse_proxy ${upstream "gatus" "app"}";
          };

          ${self.lib.tinyauthHostname}.config = "reverse_proxy ${tinyauth}";

          # `route` keeps the written order: Caddy's default order runs
          # request_header after forward_auth, which would delete the
          # identity headers tinyauth just copied in.
          ${self.lib.atriumHostname}.config = ''
            route {
              request_header -Remote-User
              request_header -Remote-Email
              request_header -Remote-Name
              request_header -Remote-Groups
              # Signed media links are public: atrium verifies the HMAC.
              # Remote-* stays stripped above, so nothing can be spoofed.
              handle /media/file/* {
                reverse_proxy ${atrium}
              }
              handle {
                forward_auth ${tinyauth} {
                  uri /api/auth/caddy
                  copy_headers Remote-User Remote-Email Remote-Groups
                }
                reverse_proxy ${atrium}
              }
            }
          '';

          ${toolSites.bill-split.hostname} = {
            content = true;
            config = serveRoot "${inputs.bill-splitter.packages.${system}.default}/dist";
          };

          ${toolSites.mdtable.hostname} = {
            content = true;
            config = serveRoot inputs.markdown-table-live-editor.packages.${system}.default;
          };

          "github.jeiang.dev".config = "redir https://github.com/jeiang{uri} 301";
        };

      anubis.origins = {
        website = {
          hosts = websiteHostnames;
          serve = serveRoot website;
        };
        # Anubis is the peer here, so the forwarded headers Caddy would
        # derive describe it (plain http from loopback), not the visitor.
        portfolio = {
          hosts = self.lib.portfolioHostnames;
          serve = servePortfolio "{header.X-Real-Ip}";
        };
      };

      services.caddy = {
        enable = true;
        package = self.packages.${system}.caddy;
        # CAA on the three zones only permits letsencrypt.org; pin here so
        # Caddy's ZeroSSL fallback never hits the CA and fails automatic HTTPS.
        acmeCA = "https://acme-v02.api.letsencrypt.org/directory";

        logFormat = ''
          level INFO
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
          # mutation); metrics are served from the metrics site instead.
          metrics

          # Without this every client_ip is a Cloudflare PoP, and a CrowdSec
          # decision bans every visitor behind that PoP.
          servers {
            trusted_proxies cloudflare {
              interval 12h
              timeout 15s
            }
            client_ip_headers Cf-Connecting-Ip
            # No UDP 443 is open, so advertising HTTP/3 only sends clients on a failed QUIC attempt.
            protocols h1 h2
          }
        '';

        extraConfig = ''
          # 2019 would collide with the admin API listener; plain http://
          # skips automatic HTTPS/ACME for this private-network-only block.
          http://${self.lib.legionNodes.${host}.privateIPv4}:${toString metricsPort} {
            metrics /metrics
          }

          ${lib.concatMapStringsSep "\n" renderSite (builtins.attrValues config.edge.sites)}
        '';

        environmentFile = config.sops.templates."caddy.env".path;
      };

      sops = {
        secrets.${self.lib.cloudflareDnsToken.secret}.sopsFile = self.lib.cloudflareDnsToken.sopsFile;

        templates."caddy.env" = {
          owner = config.services.caddy.user;
          group = config.services.caddy.group;
          restartUnits = ["caddy.service"];
          content = ''
            CLOUDFLARE_API_TOKEN=${config.sops.placeholder.${self.lib.cloudflareDnsToken.secret}}
          '';
        };
      };

      systemd.services.caddy.serviceConfig.MemoryMax = "256M";
    };
  };
}
