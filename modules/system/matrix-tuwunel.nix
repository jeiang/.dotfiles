{
  pkgs,
  config,
  ...
}: let
  port = 12312;
  clientId = "tuwunel";
  cinny = pkgs.cinny.override {
    conf = {
      homeserverList = [
        "matrix.jeiang.dev"
      ];
      allowCustomHomeservers = true;
    };
  };
in {
  services = {
    caddy = {
      virtualHosts = let
        extraConfig = ''
          reverse_proxy :${toString port}
        '';
      in {
        "matrix.jeiang.dev" = {
          inherit extraConfig;
        };
        "matrix.jeiang.dev:8448" = {
          inherit extraConfig;
        };
        "web.matrix.jeiang.dev" = {
          extraConfig = ''
            root * ${cinny}
            try_files {path} / index.html
            file_server
          '';
        };
      };
    };
    matrix-tuwunel = {
      enable = true;
      # stateDirectory = "tuwunel";
      settings = {
        global = {
          port = [port];
          unix_socket_perms = 666;
          server_name = "matrix.jeiang.dev";
          identity_provider = [
            {
              brand = "Authelia";
              client_id = clientId;
              client_secret_file = config.sops.secrets."authelia/oidc/clients/tuwunel-raw".path;
              issuer_url = "https://auth.jeiang.dev";
              callback_url = "https://matrix.jeiang.dev/_matrix/client/unstable/login/sso/callback/${clientId}";
              default = true;
            }
          ];
        };
      };
    };
    authelia.instances.main = {
      settings.identity_providers.oidc.clients = [
        {
          client_id = clientId;
          client_name = "Matrix (Tuwunel)";
          client_secret = ''{{ secret "${config.sops.secrets."authelia/oidc/clients/tuwunel".path}" }}'';
          public = false;
          audience = clientId;
          authorization_policy = "two_factor";
          redirect_uris = [
            "https://matrix.jeiang.dev/_matrix/client/v3/login/sso/redirect"
            "https://matrix.jeiang.dev/_matrix/client/unstable/login/sso/callback/${clientId}"
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
            "refresh_token"
          ];
          response_modes = [
            "form_post"
          ];
          token_endpoint_auth_method = "client_secret_post";
        }
      ];
    };
  };
  sops.secrets = {
    "authelia/oidc/clients/tuwunel".owner = "authelia-main";
    "authelia/oidc/clients/tuwunel-raw".owner = "tuwunel";
  };
}
