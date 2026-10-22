{
  self,
  config,
  ...
}: let
  unit = "netbird-proxy-atl";
  domain = "proxy-atl.jeiang.dev";
  healthPort = 9002;
  backendTlsPort = 8444;
  relay = config.legion.services.netbird-relay-atl;
  relayHost = self.lib.netbirdRelayAtlHost;
  crowdsecLapiPort = config.legion.services.crowdsec.ports.lapi;
in {
  flake.lib.netbirdProxyAtlHost = domain;

  legion.services.${unit} = {
    node = "ricklent";
    module = unit;
    units = [unit "haproxy" "caddy" "acme-.*"];
    ports = {
      health = healthPort;
      metrics = healthPort;
      backend-tls = backendTlsPort;
    };
    publicHostnames = [domain "*.${domain}"];
    firewall = [
      {
        port = relay.ports.tls;
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
        extraDomainNames = ["*.${domain}" relayHost];
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        environmentFile = config.sops.templates."${unit}-cloudflare-dns.env".path;
        group = unit;
        reloadServices = ["caddy.service"];
      };
    };

    sops = {
      secrets = {
        "netbird/proxy-atl-token" = {inherit sopsFile;};
        "netbird-proxy-atl/cloudflare-dns-token" = {inherit sopsFile;};
        "crowdsec/bouncer-netbird-proxy-atl-key" = {inherit sopsFile;};
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
        caddy.extraGroups = [unit];
      };
    };

    services.haproxy = {
      enable = true;
      config = ''
        global
          log stdout format raw local0
          maxconn 2048

        defaults
          mode tcp
          log global
          option tcplog
          timeout connect 5s
          timeout client 1h
          timeout server 1h

        frontend netbird_tls
          bind [::]:${toString relay.ports.tls} v4v6
          tcp-request inspect-delay 5s
          tcp-request content accept if { req.ssl_hello_type 1 }
          tcp-request content reject if WAIT_END
          use_backend netbird_relay if { req.ssl_sni -i ${relayHost} }
          default_backend netbird_proxy

        backend netbird_relay
          server relay 127.0.0.1:${toString relay.ports.backend-tls}

        backend netbird_proxy
          server proxy 127.0.0.1:${toString backendTlsPort} send-proxy-v2
      '';
    };

    services.caddy = {
      enable = true;
      globalConfig = ''
        auto_https off
      '';
      virtualHosts."https://${relayHost}:${toString relay.ports.backend-tls}".extraConfig = ''
        bind 127.0.0.1
        tls ${acmeCertDir}/fullchain.pem ${acmeCertDir}/key.pem
        reverse_proxy 127.0.0.1:${toString relay.ports.relay} {
          transport http {
            read_timeout 15m
          }
        }
      '';
    };

    systemd.services = {
      caddy = {
        after = ["acme-${domain}.service"];
        wants = ["acme-${domain}.service"];
      };
      ${unit} = {
        description = "NetBird reverse proxy (Atlanta)";
        after = ["network-online.target" "acme-${domain}.service"];
        wants = ["network-online.target" "acme-${domain}.service"];
        wantedBy = ["multi-user.target"];
        environment = {
          NB_PROXY_ADDRESS = "127.0.0.1:${toString backendTlsPort}";
          NB_PROXY_DOMAIN = domain;
          # Wildcard binding tolerates mesh enrollment/reconnect; only the trusted mesh can reach this port.
          NB_PROXY_HEALTH_ADDRESS = ":${toString healthPort}";
          NB_PROXY_MANAGEMENT_ADDRESS = "https://netbird.jeiang.dev";
          NB_PROXY_CERTIFICATE_DIRECTORY = acmeCertDir;
          NB_PROXY_CERTIFICATE_FILE = "fullchain.pem";
          NB_PROXY_CERTIFICATE_KEY_FILE = "key.pem";
          NB_PROXY_ACME_CERTIFICATES = "false";
          NB_PROXY_FORWARDED_PROTO = "https";
          # HAProxy preserves TLS and the original client IP; direct custom-port clients are not trusted.
          NB_PROXY_PROXY_PROTOCOL = "true";
          NB_PROXY_TRUSTED_PROXIES = "127.0.0.1/32";
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
