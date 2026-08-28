_: {
  flake.nixosModules.blocky = {config, ...}: {
    services.blocky = {
      enable = true;
      settings = {
        blocking = {
          blockType = "nxDomain";
          clientGroupsBlock.default = ["ads"];
          denylists.ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.188.69901/hosts/pro.plus.txt"
            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@37522026.188.69901/hosts/tif.txt"
          ];
        };
        customDNS.mapping = {};
        prometheus.enable = true;
        ports = {
          # 553, not 53: NetBird's embedded DNS resolver binds 53 on this host.
          dns = 553;
          http = 8000;
        };
        upstreams.groups.default = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
          "8.8.4.4"
          "9.9.9.9"
          "149.112.112.112"
          "tcp-tls:one.one.one.one:853"
          "tcp-tls:dns.google:853"
          "tcp-tls:dns.quad9.net:853"
        ];
        log = {
          level = "info";
          format = "text";
        };
      };
    };

    systemd.services.blocky = {
      after = [(config.services.netbird.clients.default.service.name + ".service")];
      wants = [(config.services.netbird.clients.default.service.name + ".service")];
      serviceConfig.MemoryMax = "512M";
    };
  };
}
