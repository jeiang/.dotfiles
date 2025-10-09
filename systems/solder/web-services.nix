{config, ...}: {
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
      configFile = ./Caddyfile;
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
  };

  users.users = {
    lldap = {
      isSystemUser = true;
      group = "lldap";
    };
  };
  users.groups.lldap = {};

  networking.firewall.allowedTCPPorts = [80 443];
  networking.firewall.allowedUDPPorts = [443];
}
