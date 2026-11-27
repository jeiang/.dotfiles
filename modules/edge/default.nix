{
  self,
  inputs,
  config,
  lib,
  ...
}: let
  legionServices = config.legion.services;
  metricsPort = 2020;
  httpsPort = 443;
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
    ports.https = httpsPort;
    publicPorts = [
      {
        port = 80;
        proto = "tcp";
      }
      {
        port = httpsPort;
        proto = "tcp";
      }
    ];
  };

  netbird.meshFlows.caddy = [{port = httpsPort;}];

  monitoring.scrape.caddy = {
    type = "edge";
    targets = self.lib.monitoringTargets "caddy" "metrics" "";
  };

  gatus.endpoints = let
    # Status alone passes an empty 200.
    home = host: {
      group = "Web";
      url = "https://${host}";
      conditions = ["[STATUS] == 200" "[BODY] == pat(*Aidan Pinard - Home*)"];
    };
  in
    {
      Website = home apex;
      "aidanpinard.co" = home "aidanpinard.co";
      "pinard.co.tt" = home "pinard.co.tt";
    }
    // lib.mapAttrs' (_: site:
      lib.nameValuePair site.title {
        group = "Web";
        url = "https://${site.hostname}";
      })
    toolSites
    // {
      # netbird.jeiang.dev is grey-clouded (DNS-only), so this reads
      # Caddy's own *.jeiang.dev wildcard cert directly, not
      # Cloudflare's edge cert as a proxied hostname would.
      "TLS certificate" = {
        group = "Edge";
        url = "https://${self.lib.netbirdDomain}/oauth2/.well-known/openid-configuration";
        interval = "1h";
        conditions = [
          "[STATUS] == 200"
          "[CERTIFICATE_EXPIRATION] > 240h"
        ];
      };
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
            config = servePortfolio "{client_ip}";
          };

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
            # Caddy 2.11 aborts a request body that is idle for 1m, which cuts NetBird's gRPC
            # streams every minute. A per-route `timeouts` cannot loosen it before 2.11.8.
            timeouts {
              read_body_idle -1s
            }
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

      systemd.services.caddy = {
        serviceConfig.MemoryMax = "256M";
        environment = self.lib.otlpTracesEnv host "caddy-edge";
      };
    };
  };
}
