{config, ...}: {
  services.caddy = {
    enable = true;
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
          roll_size 10mb
          roll_keep 100
          roll_keep_for 30d
        }
        exclude http.log.access
        format json
      }
    '';
    extraConfig = let
      authelia = config.services.authelia.instances.main;
      autheliaAddress =
        builtins.replaceStrings ["tcp://" "unix://" "?umask="] ["" "unix/" "|"] authelia.settings.server.address;
      authConfig =
        if authelia.enable
        then ''
          forward_auth ${autheliaAddress} {
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
  networking.firewall = {
    allowedTCPPorts = [80 443];
    allowedUDPPorts = [443];
  };
}
