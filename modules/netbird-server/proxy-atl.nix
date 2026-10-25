{
  self,
  config,
  ...
}: let
  unit = "netbird-proxy-atl";
  domain = "proxy-atl.jeiang.dev";
  healthPort = 9002;
  tlsPort = 443;
  crowdsecLapiPort = config.legion.services.crowdsec.ports.lapi;
in {
  flake.lib.netbirdProxyAtlHost = domain;

  legion.services.${unit} = {
    node = "ricklent";
    module = unit;
    units = [unit "acme-.*"];
    ports = {
      health = healthPort;
      metrics = healthPort;
    };
    publicHostnames = [domain "*.${domain}"];
    firewall = [
      {
        port = tlsPort;
        proto = "tcp";
        scope = "public";
      }
    ];
    firewallPortRanges = map (proto: {
      from = 40000;
      to = 45000;
      inherit proto;
      scope = "public";
    }) ["tcp" "udp"];
  };

  nixos.modules.${unit} = {
    config,
    lib,
    pkgs,
    ...
  }: let
    proxyPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.netbird-proxy;
    sopsFile = ./secrets.proxy-atl.yaml;
    acmeCertDir = config.security.acme.certs.${domain}.directory;
    lapiAddress = self.lib.legionAddress config.networking.hostName "alda";
  in {
    security.acme = {
      acceptTerms = true;
      defaults.email = "aidan@aidanpinard.co";
      certs.${domain} = {
        extraDomainNames = ["*.${domain}"];
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        environmentFile = config.sops.templates."${unit}-cloudflare-dns.env".path;
        group = unit;
      };
    };

    sops = {
      secrets = {
        "netbird/proxy-atl-token" = {inherit sopsFile;};
        "netbird-proxy-atl/cloudflare-dns-token" = {inherit sopsFile;};
        "crowdsec/bouncer-netbird-proxy-atl-key" = {
          sopsFile = ../crowdsec/secrets.agent.yaml;
        };
      };
      templates = {
        "${unit}.env" = {
          owner = unit;
          restartUnits = ["${unit}.service"];
          content = ''
            NB_PROXY_TOKEN=${config.sops.placeholder."netbird/proxy-atl-token"}
            NB_PROXY_CROWDSEC_API_KEY=${config.sops.placeholder."crowdsec/bouncer-netbird-proxy-atl-key"}
          '';
        };
        "${unit}-cloudflare-dns.env".content = ''
          CF_DNS_API_TOKEN=${config.sops.placeholder."netbird-proxy-atl/cloudflare-dns-token"}
        '';
      };
    };

    users = {
      groups.${unit} = {};
      users = {
        ${unit} = {
          isSystemUser = true;
          group = unit;
        };
      };
    };

    systemd.services = {
      ${unit} = {
        description = "NetBird reverse proxy (Atlanta)";
        after = ["network-online.target" "acme-${domain}.service"];
        wants = ["network-online.target" "acme-${domain}.service"];
        wantedBy = ["multi-user.target"];
        environment = {
          NB_PROXY_ADDRESS = ":${toString tlsPort}";
          NB_PROXY_DOMAIN = domain;
          # Wildcard binding tolerates mesh enrollment/reconnect; only the trusted mesh can reach this port.
          NB_PROXY_HEALTH_ADDRESS = ":${toString healthPort}";
          NB_PROXY_MANAGEMENT_ADDRESS = "https://netbird.jeiang.dev";
          NB_PROXY_CERTIFICATE_DIRECTORY = acmeCertDir;
          NB_PROXY_CERTIFICATE_FILE = "fullchain.pem";
          NB_PROXY_CERTIFICATE_KEY_FILE = "key.pem";
          NB_PROXY_ACME_CERTIFICATES = "false";
          NB_PROXY_FORWARDED_PROTO = "https";
          NB_PROXY_SUPPORTS_CUSTOM_PORTS = "true";
          NB_PROXY_PRIVATE = "true";
          NB_PROXY_CROWDSEC_API_URL = "http://${lapiAddress}:${toString crowdsecLapiPort}";
          NB_PROXY_LOG_LEVEL = "info";
          NB_PROXY_GEO_DATA_DIR = "/var/cache/${unit}";
        };
        serviceConfig = {
          ExecStart = lib.getExe proxyPkg;
          EnvironmentFile = [config.sops.templates."${unit}.env".path];
          Restart = "on-failure";
          RestartSec = 5;
          User = unit;
          Group = unit;
          AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
          CacheDirectory = unit;
          MemoryMax = "256M";
        };
      };
    };
  };
}
