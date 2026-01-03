{
  config,
  lib,
  ...
}: let
  netbirdAuthClientId = "netbird";
  authDomain = "auth.jeiang.dev";
in {
  # TODO: add config to allow this same file to be used on server & client, and add an option to enable server stuff
  services = {
    caddy.virtualHosts."netbird" = rec {
      hostName = "netbird.jeiang.dev";
      logFormat = null;
      extraConfig = ''
        import logging ${hostName}
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

    netbird = {
      enable = true;
      clients.default.config = let
        urlConfig = {
          Scheme = "https";
          Opaque = "";
          User = null;
          Host = "netbird.jeiang.dev:443";
          Path = "";
          RawPath = "";
          OmitHost = false;
          ForceQuery = false;
          RawQuery = "";
          Fragment = "";
          RawFragment = "";
        };
      in {
        # Set Management URL for netbird configuration file
        ManagementURL = urlConfig;
        AdminUrl = urlConfig;
      };
      useRoutingFeatures = "both";
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
    authelia.instances.main = {
      settings.identity_providers.oidc.clients = [
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
  systemd.services = {
    # reload netbird service whenever the system config changes
    ${config.services.netbird.clients.default.service.name} = {
      # caddy needs to be started before the client can access the management server
      requires = [config.systemd.services.caddy.name];
      after = [config.systemd.services.caddy.name];
      partOf = ["netbird-login.service"];
    };
    # netbird login before service starts
    netbird-login = let
      defaultClient = config.services.netbird.clients.default;
    in {
      description = "Login to self hosted netbird instance";
      before = [config.systemd.services.${defaultClient.service.name}.name];
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      inherit (config.systemd.services.${defaultClient.service.name}) preStart;
      serviceConfig = {
        ExecStart = "${lib.getExe config.services.netbird.package} login --management-url https://netbird.jeiang.dev --setup-key-file ${config.sops.secrets."netbird/client-setup-key".path}";
        User = defaultClient.user.name;
        Group = defaultClient.user.group;
        RuntimeDirectory = defaultClient.dir.baseName;
        RuntimeDirectoryMode = "0755";
        ConfigurationDirectory = defaultClient.dir.baseName;
        StateDirectory = defaultClient.dir.baseName;
        StateDirectoryMode = "0700";
        WorkingDirectory = defaultClient.dir.state;
      };
    };
    # Override the default user for coturn, there is no exposed option for it
    coturn.serviceConfig = {
      User = lib.mkForce "netbird";
      Group = lib.mkForce "netbird";
    };
  };
  users = {
    users.netbird = {
      isSystemUser = true;
      group = "netbird";
    };

    groups.netbird = {};
  };
  sops.secrets = {
    "netbird/coturn/password".owner = "netbird";
    "netbird/datastore-key".owner = "netbird";
    "netbird/coturn/salt".owner = "netbird";
    "netbird/auth-client-secret".owner = "netbird";
    "netbird/client-setup-key".owner = "netbird";
    "authelia/oidc/clients/netbird".owner = "authelia-main";
  };

  networking.firewall.trustedInterfaces = [
    config.services.netbird.clients.default.interface
  ];
}
