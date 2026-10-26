{self, ...}: let
  httpPort = 8000;
  # 553, not 53: NetBird's embedded DNS resolver binds 53 on these hosts.
  dnsPort = 553;

  service = node: module: {
    inherit node module;
    units = ["blocky"];
    ports.http = httpPort;
  };

  listen = host: port:
    if host == null
    then port
    else "${host}:${toString port}";

  mkBlocky = host: {
    config,
    lib,
    ...
  }: {
    services.blocky = {
      enable = true;
      settings = {
        blocking = {
          blockType = "nxDomain";
          clientGroupsBlock.default = ["ads"];
          loading = {
            # Answer from the cache and upstreams while the lists download.
            strategy = "fast";
            # hagezi's tif list is ~2M lines; the 5s default cuts it off mid-download.
            downloads.timeout = "2m";
          };
          denylists.ads = [
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts"
            # hagezi moved its hosts files to a legacy repository; the wildcard format is the one it lists for Blocky.
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt"
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif.txt"
          ];
        };
        caching = {
          prefetching = true;
          minTime = "5m";
        };
        prometheus.enable = true;
        ports = {
          dns = listen host dnsPort;
          http = listen host httpPort;
        };
        # Encrypted upstreams only. The bootstrap IPs resolve their names without the host resolver, which may lead back to Blocky.
        upstreams.groups.default = [
          "tcp-tls:one.one.one.one:853"
          "tcp-tls:dns.google:853"
          "tcp-tls:dns.quad9.net:853"
        ];
        bootstrapDns = [
          {
            upstream = "tcp-tls:one.one.one.one:853";
            ips = ["1.1.1.1" "1.0.0.1"];
          }
          {
            upstream = "tcp-tls:dns.quad9.net:853";
            ips = ["9.9.9.9" "149.112.112.112"];
          }
        ];
        log = {
          level = "info";
          format = "text";
        };
      };
    };

    systemd.services.blocky = lib.mkMerge [
      {
        after = [(config.services.netbird.clients.default.service.name + ".service")];
        wants = [(config.services.netbird.clients.default.service.name + ".service")];
        # The hagezi lists hold ~2.4M entries (~390 MB resident); a refresh parses the new set while the old one is live.
        serviceConfig.MemoryMax = "1G";
      }
      (lib.mkIf (host != null) {
        # The mesh address appears only once NetBird connects; keep retrying the bind until then.
        startLimitIntervalSec = 0;
        serviceConfig.RestartSec = 5;
      })
    ];
  };
in {
  legion.services = {
    blocky = service "vida" "blocky";
    blocky-ricklent = service "ricklent" "blocky-ricklent";
  };

  nixos.modules = {
    blocky = mkBlocky null;
    blocky-ricklent = mkBlocky self.lib.netbirdPeers.ricklent;
  };
}
