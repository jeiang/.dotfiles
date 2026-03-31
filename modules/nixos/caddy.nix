{
  flake.nixosModules.caddy = {config, ...}: {
    services.caddy = {
      enable = true;
      openFirewall = true;
      user = "caddy";
      group = "caddy";
      email = "aidan@aidanpinard.co";
      logFormat = ''
        output stdout
        format json
        level DEBUG
      '';
      # TODO: put all dns records on porkbun & use
      # https://caddy.community/t/how-to-use-dns-provider-modules-in-caddy-2/8148 and
      # https://wiki.nixos.org/wiki/Caddy#Plug-ins for configuring wildcard domains
      globalConfig = ''
        servers {
          protocols h1 h2 h2c h3
        }
        default_sni aidanpinard.co
        log default-file {
          output file /var/log/caddy/caddy.log {
            mode 0644
            roll_size 10mb
            roll_keep 100
            roll_keep_for 30d
          }
          exclude http.log.access
          format json
        }
        metrics {
          per_host
        }
      '';
      extraConfig = let
        autheliaEnabled = config.services.authelia.instances ? main && config.services.authelia.instances.main.enable;
        authConfig =
          if autheliaEnabled
          then let
            address = builtins.replaceStrings ["tcp://" "unix://" "?umask="] ["" "unix/" "|"] config.services.authelia.instances.main.settings.server.address;
          in ''
            forward_auth ${address} {
              uri /api/authz/forward-auth
              copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
            }
          ''
          else builtins.warn "Authelia is not enabled. No authentication will occur on protected endpoints" "";
      in ''
        (compression) {
          encode zstd gzip
        }

        (security_headers) {
          header * {
            Strict-Transport-Security "max-age=3600; includeSubDomains; preload"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            X-XSS-Protection "1; mode=block"
            -Server
            Referrer-Policy strict-origin-when-cross-origin
          }
        }

        (auth) {
          ${authConfig}
        }

        (logging) {
          log {
            hostnames {args[0]}
            output file ${config.services.caddy.logDir}/access-{args[0]}.log {
              roll_size 10mb
              roll_keep 100
              roll_keep_for 30d
            }
          }
        }
      '';
      virtualHosts = {
        "github" = rec {
          hostName = "github.jeiang.dev";
          extraConfig = ''
            import logging ${hostName}
            import compression
            import security_headers
            redir * https://github.com/jeiang permanent
          '';
        };
      };
    };
    services.prometheus.scrapeConfigs = [
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = [
              "localhost:2019"
            ];
          }
        ];
      }
    ];
    environment.etc."alloy/10-caddy.alloy".text = ''
      local.file_match "caddy" {
        path_targets = [
          {
            __path__ = "/var/log/caddy/caddy.log",
            job      = "caddy",
            log_type = "main",
          },
          {
            __path__ = "/var/log/caddy/access-*.log",
            job      = "caddy",
            log_type = "access",
          },
        ]
      }

      loki.process "caddy_json" {
        stage.json {
          expressions = {
            level        = "level",
            logger       = "logger",
            msg          = "msg",
            host         = "request.host",
            http_version = "request.proto",
            http_method  = "request.method",
            http_status  = "status",
            duration     = "duration",
            ip           = "request.remote_ip",
          }
        }

        stage.labels {
          values = {
            level        = "",
            logger       = "",
            host         = "",
            http_version = "",
            http_method  = "",
            http_status  = "",
          }
        }

        stage.structured_metadata {
          values = {
            duration = "",
            ip       = "",
          }
        }

        forward_to = [loki.write.local.receiver]
      }

      loki.source.file "caddy" {
        targets    = local.file_match.caddy.targets
        forward_to = [loki.process.caddy_json.receiver]
      }
    '';
  };
}
