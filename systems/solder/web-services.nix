{
  config,
  inputs,
  pkgs,
  ...
}: {
  services = {
    blocky = {
      enable = true;
      settings = {
        ports = {
          dns = 53;
          http = 8000;
        };
        upstreams = {
          groups = {
            default = [
              "1.1.1.1"
              "8.8.8.8"
              "8.8.4.4"
              "tcp-tls:one.one.one.one:853"
              "tcp-tls:dns.google:853"
              "tcp-tls:dns.quad9.net:853"
            ];
          };
        };
        blocking = {
          denylists = {
            ads = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
              "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/hosts/pro.plus.txt"
              "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/hosts/tif.txt"
            ];
          };
          blockType = "nxDomain";
          clientGroupsBlock = {
            default = [
              "ads"
            ];
          };
        };
      };
    };
    caddy = {
      enable = true;
      configFile = pkgs.writeText "Caddyfile" ''
        # Caddyfile
        {
          email aidan@aidanpinard.co
          servers {
            protocols h1 h2 h2c h3
          }
          default_sni aidanpinard.co
          log default {
            output stdout
            format json
          }
        }

        (compression) {
          encode zstd gzip
        }

        (auth) {
          forward_auth authelia:80 {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
        }

        (logging) {
          log output-file {
            output file /var/log/caddy/access.log {
              roll_size 10mb
              roll_keep 5
              roll_keep_for 48h
            }
            format json
          }
          log console-output {
            output stdout
            format json
          }
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

        jeiang.dev, aidanpinard.co, pinard.co.tt {
          import compression
          import logging
          import security_headers
          reverse_proxy localhost:8080
        }

        github.jeiang.dev {
          redir * https://github.com/jeiang permanent
        }

        auth.jeiang.dev {
          import logging
          reverse_proxy authelia:80
        }

        ldap.jeiang.dev {
          import compression
          import security_headers
          import logging
          reverse_proxy localhost:17170
        }

        dns.jeiang.dev {
          import compression
          import logging

          reverse_proxy localhost:8000
        }
      '';
      enableReload = true;
    };
    lldap = {
      enable = true;
      environment = {
        TZ = "UTC";
      };
      settings = {
        http_url = "https://ldap.jeiang.dev";
        http_port = 17170;
        ldap_port = 3890;
        ldap_base_dn = "dc=jeiang,dc=dev";
        ldap_user_email = "otakuman86@gmail.com";
        ldap_user_pass_file = config.sops.secrets."lldap/admin-pw".path;
        jwt_secret_file = config.sops.secrets."lldap/jwt".path;
        force_ldap_user_pass_reset = "always";
        smtp_options = {
          enable_password_reset = true;
          server = "smtp.porkbun.com";
          port = 50587;
          smtp_encryption = "STARTTLS";
          user = "mail@jeiang.dev";
          from = "User Management (jeiang.dev) <authelia@jeiang.dev>";
          password_file = config.sops.secrets."lldap/mail-pw".path;
        };
      };
    };
    # netbird = let
    #   clientId = "netbird";
    #   ssoDomain = "auth.jeiang.dev";
    # in {
    #   enable = true;
    #   useRoutingFeatures = "both";
    #   server = {
    #     enable = true;
    #     domain = "netbird.jeiang.dev";
    #     signal = {
    #       enable = true;
    #       port = 8012;
    #       metricsPort = 9091;
    #     };
    #     coturn = {
    #       enable = true;
    #       domain = config.services.netbird.server.domain;
    #       user = "netbird";
    #       passwordFile = config.sops.secrets."netbird/coturn-pw".path;
    #     };
    #     dashboard = {
    #       enable = true;
    #       domain = config.services.netbird.server.domain;
    #       settings = {
    #         NETBIRD_MGMT_API_ENDPOINT = "https://netbird.jeiang.dev:443";
    #         NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://netbird.jeiang.dev:443";
    #         AUTH_AUDIENCE = clientId;
    #         AUTH_CLIENT_ID = clientId;
    #         AUTH_CLIENT_SECRET = config.sops.secrets."netbird/coturn-pw".path;
    #         AUTH_AUTHORITY = "https://${ssoDomain}";
    #         USE_AUTH0 = "false";
    #         AUTH_SUPPORTED_SCOPES = "openid offline_access profile email groups";
    #         AUTH_REDIRECT_URI = "/peers";
    #         AUTH_SILENT_REDIRECT_URI = "/add-peers";
    #         NETBIRD_TOKEN_SOURCE = "idToken";
    #         NGINX_SSL_PORT = "443";
    #       };
    #     };
    #     management = {
    #       port = 23461;
    #       oidcConfigEndpoint = "https://${ssoDomain}/.well-known/openid-configuration";
    #     };
    #   };
    # };
  };

  systemd.services.website = {
    enable = true;
    description = "jeiang.dev website";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    environment = {
      SERVER_PORT = "8080";
    };
    serviceConfig = let
      src = inputs.website.packages.${pkgs.system}.default;
      website =
        pkgs.runCommand "website" {
          buildInputs = with pkgs; [makeWrapper jdk21_headless];
        } ''
          mkdir $out
          ln -s ${src}/* $out
          # Except the bin folder
          rm $out/bin
          mkdir $out/bin

          makeWrapper ${src}/bin/website $out/bin/website --set JAVA_HOME ${pkgs.jdk21_headless}
        '';
    in {
      User = "website";
      Group = "website";
      DynamicUser = true;
      ExecStart = "${website}/bin/website";
      Restart = "on-failure";
      MemoryHigh = "100M";
      MemoryMax = "200M";
    };
  };
  users = {
    users = {
      lldap = {
        isSystemUser = true;
        group = "lldap";
      };
      netbird = {
        isSystemUser = true;
        group = "netbird";
      };
    };
    groups = {
      lldap = {};
      netbird = {};
    };
  };

  networking.firewall.allowedTCPPorts = [80 443];
  networking.firewall.allowedUDPPorts = [443];
}
