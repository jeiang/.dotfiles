{config, ...}: let
  autheliaAddress = "localhost:8081";
  authDomain = "auth.jeiang.dev";
in {
  services = {
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
              domain = "chat.jeiang.dev";
              policy = "one_factor";
              subject = [
                "group:chat"
              ];
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
    caddy.virtualHosts = {
      "authelia" = rec {
        hostName = authDomain;
        logFormat = null;
        extraConfig = ''
          import logging ${hostName}
          import compression
          reverse_proxy ${autheliaAddress}
        '';
      };
      "lldap" = rec {
        hostName = "ldap.jeiang.dev";
        logFormat = null;
        extraConfig = ''
          import logging ${hostName}
          import compression
          import security_headers
          reverse_proxy localhost:${toString config.services.lldap.settings.http_port}
        '';
      };
    };
  };

  # Allow authelia to write to logs directory
  systemd.services.authelia-main.serviceConfig.LogsDirectory = "authelia-main";

  users = {
    users.lldap = {
      isSystemUser = true;
      group = "lldap";
    };
    groups.lldap = {};
  };
  sops.secrets = {
    "lldap/jwt".owner = "lldap";
    "lldap/seed".owner = "lldap";
    "lldap/admin-pw".owner = "lldap";
    "lldap/mail-pw".owner = "lldap";
    "authelia/ldap-pw".owner = "authelia-main";
    "authelia/mail/password".owner = "authelia-main";
    "authelia/mail/username".owner = "authelia-main";
    "authelia/storage-encryption-key".owner = "authelia-main";
    "authelia/session-secret-key".owner = "authelia-main";
    "authelia/jwt-secret-key".owner = "authelia-main";
    "authelia/oidc/hmac-secret".owner = "authelia-main";
    "authelia/oidc/issuer-key".owner = "authelia-main";
  };
}
