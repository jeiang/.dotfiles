{
  config,
  inputs,
  pkgs,
  ...
}: let
  websitePort = "8080";
  autheliaUnixSocket = "/var/run/authelia.sock";
  autheliaUnixSocketUmask = "0227";
  netbirdAuthClientId = "netbird";
  authDomain = "auth.jeiang.dev";
in {
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

        (auth) {
          forward_auth unix/${autheliaUnixSocket}|${autheliaUnixSocketUmask} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
        }

        test.jeiang.dev {
          import compression
          import logging
          import security_headers
          import auth

          respond "works (thumbs up)"
        }

        jeiang.dev, aidanpinard.co, pinard.co.tt {
          import compression
          import logging
          import security_headers
          reverse_proxy localhost:${websitePort}
        }

        github.jeiang.dev {
          redir * https://github.com/jeiang permanent
        }

        ${authDomain} {
          import logging
          reverse_proxy unix/${autheliaUnixSocket}|${autheliaUnixSocketUmask}
        }

        ldap.jeiang.dev {
          import compression
          import security_headers
          import logging
          reverse_proxy localhost:${toString config.services.lldap.settings.http_port}
        }

        dns.jeiang.dev {
          import compression
          import logging

          reverse_proxy localhost:${toString config.services.blocky.settings.ports.http}
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
    authelia.instances.main = {
      enable = true;
      secrets = {
        storageEncryptionKeyFile = config.sops.secrets."authelia/storage-encryption-key".path;
        jwtSecretFile = config.sops.secrets."authelia/jwt-secret-key".path;
        sessionSecretFile = config.sops.secrets."authelia/session-secret-key".path;
        oidcHmacSecretFile = config.sops.secrets."authelia/oidc/hmac-secret".path;
        oidcIssuerPrivateKeyFile = config.sops.secrets."authelia/oidc/issuer-key".path;
      };
      environmentVariables = {
        TZ = "UTC";
        AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = config.sops.secrets."authelia/mail/password".path;
        AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = config.sops.secrets."authelia/ldap-pw".path;
        X_AUTHELIA_CONFIG_FILTERS = "template";
      };
      settings = {
        theme = "light";
        server = {
          address = "unix://${autheliaUnixSocket}?umask=${autheliaUnixSocketUmask}";
        };
        log = {
          level = "debug";
          keep_stdout = true;
        };
        totp = {
          issuer = "jeiang.dev";
        };
        authentication_backend = {
          password_reset = {
            disable = false;
          };
          refresh_interval = "5m";
          ldap = {
            address = "ldap://0.0.0.0:${toString config.services.lldap.settings.ldap_port}";
            implementation = "lldap";
            base_dn = "dc=jeiang,dc=dev";
            user = "uid=authelia,ou=people,dc=jeiang,dc=dev";
            users_filter = "(&(|({username_attribute}={input})({mail_attribute}={input}))(objectClass=person))";
          };
        };
        access_control = {
          default_policy = "deny";
          rules = [
            {
              domain = "jeiang.dev";
              policy = "bypass";
            }
            {
              domain = "stats.jeiang.dev";
              policy = "two_factor";
              subject = [
                "group:admin"
                "group:monitoring"
              ];
            }
          ];
        };
        identity_providers = {
          oidc = {
            cors = {
              allowed_origins_from_client_redirect_uris = true;
              endpoints = [
                "userinfo"
                "authorization"
                "token"
                "revocation"
                "introspection"
              ];
            };
            clients = [
              {
                client_id = netbirdAuthClientId;
                client_name = "Netbird";
                client_secret = ''{{ secret "${config.sops.secrets."authelia/oidc/clients/netbird".path}" }}'';
                public = false;
                audience = netbirdAuthClientId;
                authorization_policy = "two_factor";
                require_pkce = true;
                pkce_challenge_method = "S256";
                redirect_uris = [
                  "https://netbird.jeiang.dev"
                  "https://netbird.jeiang.dev/peers"
                  "https://netbird.jeiang.dev/add-peers"
                  "http://localhost:53000"
                ];
                scopes = [
                  "openid"
                  "email"
                  "profile"
                  "offline_access"
                  "groups"
                ];
                response_types = [
                  "code"
                ];
                grant_types = [
                  "authorization_code"
                ];
                token_endpoint_auth_method = "client_secret_post";
              }
            ];
          };
        };
        session = {
          cookies = [
            {
              name = "jeiangdev_session";
              domain = "jeiang.dev";
              authelia_url = "https://${authDomain}";
            }
          ];
        };
        regulation = {
          max_retries = 3;
          find_time = "2 minutes";
          ban_time = "5 minutes";
        };
        storage = {
          local = {
            path = "/var/db/authelia/db.sqlite3";
          };
        };
        notifier = {
          smtp = {
            username = ''{{ secret "${config.sops.secrets."authelia/mail/username".path}" }}'';
            address = "smtp://smtp.porkbun.com:50587";
            sender = "Authelia (jeiang.dev) <mail@jeiang.dev>";
            identifier = "jeiang.dev";
            subject = "[Authelia] {title}";
          };
        };
      };
    };
    netbird = {
      enable = false;
      useRoutingFeatures = "both";
      server = {
        enable = false;
        domain = "netbird.jeiang.dev";
        signal = {
          enable = false;
          port = 8012;
          metricsPort = 9091;
        };
        coturn = {
          enable = false;
          inherit (config.services.netbird.server) domain;
          user = "netbird";
          passwordFile = config.sops.secrets."netbird/coturn/password".path;
        };
        dashboard = {
          enable = false;
          inherit (config.services.netbird.server) domain;
          settings = {
            NETBIRD_MGMT_API_ENDPOINT = "https://netbird.jeiang.dev:443";
            NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://netbird.jeiang.dev:443";
            AUTH_AUDIENCE = netbirdAuthClientId;
            AUTH_CLIENT_ID = netbirdAuthClientId;
            AUTH_CLIENT_SECRET = config.sops.secrets."netbird/auth-client-secret".path;
            AUTH_AUTHORITY = "https://${authDomain}";
            USE_AUTH0 = "false";
            AUTH_SUPPORTED_SCOPES = "openid offline_access profile email groups";
            AUTH_REDIRECT_URI = "/peers";
            AUTH_SILENT_REDIRECT_URI = "/add-peers";
            NETBIRD_TOKEN_SOURCE = "idToken";
            NGINX_SSL_PORT = "443";
          };
        };
        management = {
          port = 23461;
          oidcConfigEndpoint = "https://${authDomain}/.well-known/openid-configuration";
          disableSingleAccountMode = true;
          dnsDomain = "jeiang.vpn";
          disableAnonymousMetrics = true;
          settings = {
            DataStoreEncryptionKey._secret = config.sops.secrets."netbird/datastore-key".path;
            DeviceAuthorizationFlow = {
              Provider = "hosted";
              ProviderConfig = {
                Audience = netbirdAuthClientId;
                AuthorizationEndpoint = "";
                ClientID = netbirdAuthClientId;
                ClientSecret = config.sops.secrets."netbird/auth-client-secret".path;
                TokenEndpoint = "https://${authDomain}/api/oidc/token";
                DeviceAuthEndpoint = "https://${authDomain}/api/oidc/device-authorization";
                Domain = authDomain;
                RedirectURLs = null;
                DisablePromptLogin = false;
                LoginFlag = 0;
                Scope = "openid profile email";
                UseIDToken = false;
              };
            };
            DisableDefaultPolicy = true;
            HttpConfig = {
              AuthAudience = netbirdAuthClientId;
              AuthIssuer = "https://${authDomain}";
              AuthKeysLocation = "https://${authDomain}/jwks.json";
              AuthUserIDClaim = "";
              CertFile = "";
              CertKey = "";
              IdpSignKeyRefreshEnabled = true;
              OIDCConfigEndpoint = "https://${authDomain}/.well-known/openid-configuration";
            };
            IdpManagerConfig = {
              Auth0ClientCredentials = null;
              AzureClientCredentials = null;
              ClientConfig = null;
              ExtraConfig = null;
              KeycloakClientCredentials = null;
              ZitadelClientCredentials = null;
            };
            PKCEAuthorizationFlow = {
              ProviderConfig = {
                Audience = netbirdAuthClientId;
                AuthorizationEndpoint = "https://${authDomain}/api/oidc/authorization";
                ClientID = netbirdAuthClientId;
                ClientSecret = config.sops.secrets."netbird/auth-client-secret".path;
                DisablePromptLogin = false;
                Domain = "";
                LoginFlag = 0;
                RedirectURLs = ["http://localhost:53000"];
                Scope = "openid profile email";
                TokenEndpoint = "https://${authDomain}/api/oidc/token";
                UseIDToken = true;
              };
            };
            Stuns = [
              {
                Proto = "udp";
                URI = "stun:${config.services.netbird.server.coturn.domain}:3478";
                Username = "";
                Password = "";
              }
            ];
            TURNConfig = {
              Secret._secret = config.sops.secrets."netbird/coturn/salt".path;
              TimeBasedCredentials = false;
              CredentialsTTL = "24h0m0s";
              Turns = [
                {
                  Proto = "udp";
                  URI = "turn:${config.services.netbird.server.coturn.domain}:3478";
                  Username = config.services.netbird.server.coturn.user;
                  Password._secret = config.sops.secrets."netbird/coturn/password".path;
                }
              ];
            };
          };
        };
      };
    };
  };

  systemd.services.website = {
    enable = true;
    description = "jeiang.dev website";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    environment = {
      SERVER_PORT = websitePort;
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
      authelia = {
        isSystemUser = true;
        group = "authelia";
      };
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
      authelia = {};
    };
  };
  systemd.tmpfiles.settings = {
    "10-authelia-dirs" = {
      "/var/db/authelia" = {
        d = {
          mode = "0755";
          user = "authelia-main";
          group = "authelia-main";
        };
      };
    };
  };
  sops.secrets = {
    "lldap/jwt".owner = "lldap";
    "lldap/seed".owner = "lldap";
    "lldap/admin-pw".owner = "lldap";
    "lldap/mail-pw".owner = "lldap";
    "netbird/coturn/password".owner = "netbird";
    "netbird/datastore-key".owner = "netbird";
    "netbird/coturn/salt".owner = "netbird";
    "netbird/auth-client-secret".owner = "netbird";
    "authelia/ldap-pw".owner = "authelia-main";
    "authelia/mail/password".owner = "authelia-main";
    "authelia/mail/username".owner = "authelia-main";
    "authelia/storage-encryption-key".owner = "authelia-main";
    "authelia/session-secret-key".owner = "authelia-main";
    "authelia/jwt-secret-key".owner = "authelia-main";
    "authelia/oidc/hmac-secret".owner = "authelia-main";
    "authelia/oidc/issuer-key".owner = "authelia-main";
    "authelia/oidc/clients/netbird".owner = "authelia-main";
  };

  networking.firewall.allowedTCPPorts = [80 443];
  networking.firewall.allowedUDPPorts = [443];
}
