{
  lib,
  config,
  ...
}: {
  services = {
    caddy.virtualHosts."blocky-dns-over-https" = rec {
      hostName = "dns.jeiang.dev";
      extraConfig = ''
        import compression
        import logging ${hostName}
        reverse_proxy localhost:${toString config.services.blocky.settings.ports.http}
      '';
    };
    blocky = {
      enable = true;
      settings = {
        ports = {
          dns = lib.mkDefault 553;
          http = lib.mkDefault 8000;
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
  };
}
