{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  websitePort = "8080";
  autheliaAddress = "localhost:8081";
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
      user = "caddy";
      group = "caddy";
      email = "aidan@aidanpinard.co";
      logFormat = ''
        output stdout
        format json
        level DEBUG
      '';
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
          format json
        }
      '';
      extraConfig = ''
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
          forward_auth ${autheliaAddress} {
            uri /api/authz/forward-auth
            copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
          }
        }
      '';
      virtualHosts = let
        createLogFormat = hostName: {
          logFormat = ''
            output file ${config.services.caddy.logDir}/access-${hostName}.log {
              roll_size 10mb
              roll_keep 100
              roll_keep_for 30d
            }
          '';
        };
      in {
        "main" = rec {
          hostName = "jeiang.dev";
          serverAliases = ["aidanpinard.co" "pinard.co.tt"];
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import compression
            import security_headers
            reverse_proxy localhost:${websitePort}
          '';
        };
        "github" = rec {
          hostName = "github.jeiang.dev";
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import compression
            import security_headers
            redir * https://github.com/jeiang permanent
          '';
        };
        "authelia" = rec {
          hostName = authDomain;
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import compression
            reverse_proxy ${autheliaAddress}
          '';
        };
        "lldap" = rec {
          hostName = "ldap.jeiang.dev";
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import compression
            import security_headers
            reverse_proxy localhost:${toString config.services.lldap.settings.http_port}
          '';
        };
        "blocky-dns-over-https" = rec {
          hostName = "dns.jeiang.dev";
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import compression
            reverse_proxy localhost:${toString config.services.blocky.settings.ports.http}
          '';
        };
        "netbird" = rec {
          hostName = "netbird.jeiang.dev";
          inherit (createLogFormat hostName) logFormat;
          extraConfig = ''
            import security_headers

            # reverse_proxy /relay* relay:80
            reverse_proxy /signalexchange.SignalExchange/* h2c://localhost:${toString config.services.netbird.server.signal.port}
            reverse_proxy /api/* localhost:${toString config.services.netbird.server.management.port}
            reverse_proxy /management.ManagementService/* h2c://localhost:${toString config.services.netbird.server.management.port}

            root ${config.services.netbird.server.dashboard.finalDrv}
            # Handle WASM files with specific content type
            @wasm-files path /netbird.wasm /ironrdp-pkg/ironrdp_web_bg.wasm
            handle @wasm-files {
              header Content-Type application/wasm
            }

            # Try files with fallback
            try_files {path} {path}.html {path}/

            # Serve static files
            file_server
          '';
        };
      };
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
          address = "tcp://${autheliaAddress}";
        };
        log = {
          level = "debug";
          keep_stdout = true;
          file_path = "/var/log/authelia-main/authelia.log";
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
            {
              domain = "test.jeiang.dev";
              policy = "two_factor";
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
            path = "/var/lib/authelia-main/db.sqlite3";
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
      useRoutingFeatures = "both";
      services.netbird.clients.default = {
        port = 51820;
        name = "netbird";
        systemd.name = "netbird";
        interface = "wt0";
        hardened = false;
        environment = {
          NB_MANAGEMENT_URL = "https://netbird.jeiang.dev";
          NB_SETUP_KEY = "544D3A08-7CD2-4C72-8FF9-06C2445F18B0";
          NB_DISABLE_PROFILES = "true";
        };
      };
      server = {
        enable = true;
        domain = "netbird.jeiang.dev";
        signal = {
          enable = true;
          port = 8012;
          metricsPort = 9091;
        };
        coturn = {
          enable = true;
          inherit (config.services.netbird.server) domain;
          user = "netbird";
          passwordFile = config.sops.secrets."netbird/coturn/password".path;
        };
        dashboard = {
          enable = true;
          inherit (config.services.netbird.server) domain;
          settings = {
            AUTH_AUDIENCE = netbirdAuthClientId;
            AUTH_CLIENT_ID = netbirdAuthClientId;
            # IDK how to have this read at check time
            # seems to be exposed in the frontend js anyways so...
            # see https://github.com/netbirdio/netbird/issues/4188
            AUTH_CLIENT_SECRET = lib.mkForce "_SqWC1arJ_Aeh40Leu9UnnXabG0MtFMqa0.HdJK5~8~TEZhX4KGNYHzKvnkezDO1JoNHEKWz";
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
          disableSingleAccountMode = false;
          singleAccountModeDomain = "netbird.jeiang.dev";
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
                ClientSecret._secret = config.sops.secrets."netbird/auth-client-secret".path;
                TokenEndpoint = "https://${authDomain}/api/oidc/token";
                DeviceAuthEndpoint = "https://${authDomain}/api/oidc/device-authorization";
                Domain = authDomain;
                RedirectURLs = null;
                DisablePromptLogin = false;
                LoginFlag = 0;
                Scope = "openid profile email";
                UseIDToken = true;
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
                ClientID = netbirdAuthClientId;
                ClientSecret._secret = config.sops.secrets."netbird/auth-client-secret".path;
                Domain = "";
                Audience = netbirdAuthClientId;
                TokenEndpoint = "https://${authDomain}/api/oidc/token";
                DeviceAuthEndpoint = "";
                AuthorizationEndpoint = "https://${authDomain}/api/oidc/authorization";
                Scope = "openid profile email";
                UseIDToken = true;
                RedirectURLs = ["http://localhost:53000"];
                DisablePromptLogin = false;
                LoginFlag = 0;
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
  systemd.services = {
    # Override the default user for coturn, there is no exposed option for it
    coturn.serviceConfig = {
      User = lib.mkForce "netbird";
      Group = lib.mkForce "netbird";
    };
    # Allow authelia to write to logs directory
    authelia-main.serviceConfig = {
      LogsDirectory = "authelia-main";
    };
    website = {
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
      authelia = {};
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
