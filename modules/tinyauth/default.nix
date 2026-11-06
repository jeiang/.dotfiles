{self, ...}: let
  port = 3000;
in {
  legion.services.tinyauth = {
    node = "alda";
    module = "tinyauth";
    units = ["tinyauth"];
    ports.app = port;
  };

  flake.lib.tinyauthHostname = "tinyauth.jeiang.dev";

  # Forward-auth gate for edge vhosts that have no login of their own; logs
  # in through Pocket ID. Colocated with Caddy so forward_auth stays on
  # loopback.
  nixos.modules.tinyauth = {config, ...}: let
    appUrl = "https://${self.lib.tinyauthHostname}";
    pocketId = self.lib.pocketIdUrl;
    sopsFile = ./secrets.yaml;
  in {
    services.tinyauth = {
      enable = true;
      environmentFile = config.sops.templates."tinyauth.env".path;
      settings = {
        APPURL = appUrl;
        SERVER_ADDRESS = "127.0.0.1";
        SERVER_PORT = port;
        AUTH_TRUSTEDPROXIES = "127.0.0.1";
        AUTH_SECURECOOKIE = true;
        OAUTH_AUTOREDIRECT = "pocketid";
        OAUTH_PROVIDERS_POCKETID_NAME = "Pocket ID";
        OAUTH_PROVIDERS_POCKETID_AUTHURL = "${pocketId}/authorize";
        OAUTH_PROVIDERS_POCKETID_TOKENURL = "${pocketId}/api/oidc/token";
        OAUTH_PROVIDERS_POCKETID_USERINFOURL = "${pocketId}/api/oidc/userinfo";
        OAUTH_PROVIDERS_POCKETID_REDIRECTURL = "${appUrl}/api/oauth/callback/pocketid";
        OAUTH_PROVIDERS_POCKETID_SCOPES = "openid email profile groups";
        APPS_ATRIUM_CONFIG_DOMAIN = self.lib.atriumHostname;
        APPS_ATRIUM_OAUTH_GROUPS = "atrium_access";
      };
    };

    systemd.services.tinyauth.serviceConfig.MemoryMax = "64M";

    sops = {
      secrets = {
        "tinyauth/pocket-id-client-id" = {inherit sopsFile;};
        "tinyauth/pocket-id-client-secret" = {inherit sopsFile;};
      };
      templates."tinyauth.env" = {
        owner = config.services.tinyauth.user;
        restartUnits = ["tinyauth.service"];
        content = ''
          TINYAUTH_OAUTH_PROVIDERS_POCKETID_CLIENTID=${config.sops.placeholder."tinyauth/pocket-id-client-id"}
          TINYAUTH_OAUTH_PROVIDERS_POCKETID_CLIENTSECRET=${config.sops.placeholder."tinyauth/pocket-id-client-secret"}
        '';
      };
    };
  };
}
