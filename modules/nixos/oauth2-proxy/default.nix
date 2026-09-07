{self, ...}: {
  flake.nixosModules.oauth2-proxy = {config, ...}: let
    sopsFile = ./secrets.yaml;
  in {
    services.oauth2-proxy = {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = "https://auth.jeiang.dev";
      keyFile = config.sops.templates."oauth2-proxy.env".path;
      redirectURL = "https://wger.jeiang.dev/oauth2/callback";
      httpAddress = "http://127.0.0.1:${toString self.lib.ports.legion-node1.oauth2-proxy}";
      email.domains = ["*"];
      scope = "openid email profile";
      reverseProxy = true;
      trustedProxyIP = ["127.0.0.1"];
      setXauthrequest = true;
      extraConfig = {
        skip-provider-button = true;
        code-challenge-method = "S256";
        user-id-claim = "preferred_username";
      };
    };

    systemd.services.oauth2-proxy.serviceConfig.MemoryMax = "64M";

    sops = {
      secrets = {
        "oauth2-proxy/client-id" = {inherit sopsFile;};
        "oauth2-proxy/client-secret" = {inherit sopsFile;};
        "oauth2-proxy/cookie-secret" = {inherit sopsFile;};
      };
      templates."oauth2-proxy.env" = {
        restartUnits = ["oauth2-proxy.service"];
        content = ''
          OAUTH2_PROXY_CLIENT_ID=${config.sops.placeholder."oauth2-proxy/client-id"}
          OAUTH2_PROXY_CLIENT_SECRET=${config.sops.placeholder."oauth2-proxy/client-secret"}
          OAUTH2_PROXY_COOKIE_SECRET=${config.sops.placeholder."oauth2-proxy/cookie-secret"}
        '';
      };
    };
  };
}
